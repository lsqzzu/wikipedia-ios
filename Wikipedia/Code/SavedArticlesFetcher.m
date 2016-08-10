
#import "SavedArticlesFetcher_Testing.h"

#import "Wikipedia-Swift.h"
#import "WMFArticleFetcher.h"
#import "MWKImageInfoFetcher.h"

#import "MWKDataStore.h"
#import "MWKSavedPageList.h"
#import "MWKArticle.h"
#import "MWKImage+CanonicalFilenames.h"
#import "WMFURLCache.h"
#import "WMFImageURLParsing.h"
#import "UIScreen+WMFImageWidth.h"
#import "WMFTaskGroup.h"

static DDLogLevel const WMFSavedArticlesFetcherLogLevel = DDLogLevelDebug;

#undef LOG_LEVEL_DEF
#define LOG_LEVEL_DEF WMFSavedArticlesFetcherLogLevel

NS_ASSUME_NONNULL_BEGIN

@interface SavedArticlesFetcher ()

@property (nonatomic, strong, readwrite) dispatch_queue_t accessQueue;

@property (nonatomic, strong) MWKDataStore* dataStore;
@property (nonatomic, strong) MWKSavedPageList* savedPageList;
@property (nonatomic, strong) WMFArticleFetcher* articleFetcher;
@property (nonatomic, strong) WMFImageController* imageController;
@property (nonatomic, strong) MWKImageInfoFetcher* imageInfoFetcher;

@property (nonatomic, strong) NSMutableDictionary<NSURL*, AnyPromise*>* fetchOperationsByArticleTitle;
@property (nonatomic, strong) NSMutableDictionary<NSURL*, NSError*>* errorsByArticleTitle;

- (instancetype)initWithDataStore:(MWKDataStore*)dataStore
                    savedPageList:(MWKSavedPageList*)savedPageList
                   articleFetcher:(WMFArticleFetcher*)articleFetcher
                  imageController:(WMFImageController*)imageController
                 imageInfoFetcher:(MWKImageInfoFetcher*)imageInfoFetcher NS_DESIGNATED_INITIALIZER;
@end

@implementation SavedArticlesFetcher

@dynamic fetchFinishedDelegate;

#pragma mark - NSObject

static SavedArticlesFetcher* _articleFetcher = nil;

- (instancetype)initWithDataStore:(MWKDataStore*)dataStore
                    savedPageList:(MWKSavedPageList*)savedPageList
                   articleFetcher:(WMFArticleFetcher*)articleFetcher
                  imageController:(WMFImageController*)imageController
                 imageInfoFetcher:(MWKImageInfoFetcher*)imageInfoFetcher {
    NSParameterAssert(dataStore);
    NSParameterAssert(savedPageList);
    NSParameterAssert(articleFetcher);
    NSParameterAssert(imageController);
    NSParameterAssert(imageInfoFetcher);
    self = [super init];
    if (self) {
        self.accessQueue                   = dispatch_queue_create("org.wikipedia.savedarticlesarticleFetcher.accessQueue", DISPATCH_QUEUE_SERIAL);
        self.fetchOperationsByArticleTitle = [NSMutableDictionary new];
        self.errorsByArticleTitle          = [NSMutableDictionary new];
        self.dataStore                     = dataStore;
        self.articleFetcher                = articleFetcher;
        self.imageController               = imageController;
        self.savedPageList                 = savedPageList;
        self.imageInfoFetcher              = imageInfoFetcher;
    }
    return self;
}

- (instancetype)initWithDataStore:(MWKDataStore*)dataStore
                    savedPageList:(MWKSavedPageList*)savedPageList {
    return [self initWithDataStore:dataStore
                     savedPageList:savedPageList
                    articleFetcher:[[WMFArticleFetcher alloc] initWithDataStore:dataStore]
                   imageController:[WMFImageController sharedInstance]
                  imageInfoFetcher:[[MWKImageInfoFetcher alloc] init]];
}

#pragma mark - Public

- (void)start {
    [self fetchUncachedArticlesInSavedPages];
    [self observeSavedPages];
}

- (void)stop {
    [self unobserveSavedPages];
    [self cancelFetchForSavedPages];
}

#pragma mark - Observing

- (void)savedPageWasAdded:(NSNotification*)note {
    NSURL* url = note.userInfo[MWKURLKey];
    [self fetchUncachedArticleURLs:@[url]];
}

- (void)savedPageWasRemoved:(NSNotification*)note {
    NSURL* url = note.userInfo[MWKURLKey];
    [self cancelFetchForArticleURL:url];
}

- (void)observeSavedPages {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(savedPageWasAdded:) name:MWKSavedPageListDidSaveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(savedPageWasRemoved:) name:MWKSavedPageListDidUnsaveNotification object:nil];
}

- (void)unobserveSavedPages {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Fetch

- (void)fetchUncachedEntries:(NSArray<MWKHistoryEntry*>*)insertedEntries {
    if (!insertedEntries.count) {
        return;
    }
    [self fetchUncachedArticleURLs:[insertedEntries valueForKey:WMF_SAFE_KEYPATH([MWKHistoryEntry new], url)]];
}

- (void)fetchUncachedArticlesInSavedPages {
    dispatch_block_t didFinishLegacyMigration = ^{
        [[NSUserDefaults standardUserDefaults] wmf_setDidFinishLegacySavedArticleImageMigration:YES];
    };
    if ([self.savedPageList numberOfItems] == 0) {
        didFinishLegacyMigration();
        return;
    }

    WMFTaskGroup* group = [WMFTaskGroup new];
    [self.savedPageList enumerateItemsWithBlock:^(MWKHistoryEntry* _Nonnull entry, BOOL* _Nonnull stop) {
        [group enter];
        dispatch_async(self.accessQueue, ^{
            [self fetchArticleURL:entry.url failure:^(NSError* error) {
                [group leave];
            } success:^{
                [group leave];
            }];
        });
    }];
    [group waitInBackgroundWithCompletion:didFinishLegacyMigration];
}

- (void)fetchUncachedArticleURLs:(NSArray<NSURL*>*)urls {
    if (!urls.count) {
        return;
    }
    for (NSURL* url in urls) {
        dispatch_async(self.accessQueue, ^{
            [self fetchArticleURL:url failure:^(NSError* error) {
            } success:^{
            }];
        });
    }
}

- (void)fetchArticleURL:(NSURL*)articleURL failure:(WMFErrorHandler)failure success:(WMFSuccessHandler)success {
    // NOTE: must check isCached to determine that all article data has been downloaded
    MWKArticle* articleFromDisk = [self.dataStore articleWithURL:articleURL];
    @weakify(self);
    if (articleFromDisk.isCached) {
        // only fetch images if article was cached
        [self downloadImageDataForArticle:articleFromDisk failure:failure success:success];
    } else {
        /*
           don't use "finallyOn" to remove the promise from our tracking dictionary since it has to be removed
           immediately in order to ensure accurate progress & error reporting.
         */
        self.fetchOperationsByArticleTitle[articleURL] =
            [self.articleFetcher fetchArticleForURL:articleURL progress:NULL].thenOn(self.accessQueue, ^(MWKArticle* article){
            @strongify(self);
            [self downloadImageDataForArticle:article failure:^(NSError* error) {
                dispatch_async(self.accessQueue, ^{
                    [self didFetchArticle:article url:articleURL error:error];
                    failure(error);
                });
            } success:^{
                dispatch_async(self.accessQueue, ^{
                    [self didFetchArticle:article url:articleURL error:nil];
                    success();
                });
            }];
        }).catch(^(NSError* error){
            if (!self) {
                return;
            }
            dispatch_async(self.accessQueue, ^{
                [self didFetchArticle:nil url:articleURL error:error];
            });
        });
    }
}

- (void)downloadImageDataForArticle:(MWKArticle*)article failure:(WMFErrorHandler)failure success:(WMFSuccessHandler)success {
    if (![[NSUserDefaults standardUserDefaults] wmf_didFinishLegacySavedArticleImageMigration]) {
        WMF_TECH_DEBT_TODO(This legacy migration can be removed after enough users upgrade to 5.0 .5)
        [self migrateLegacyImagesInArticle : article];
    }
    [self fetchAllImagesInArticle:article failure:^(NSError* error) {
        failure([NSError wmf_savedPageImageDownloadError]);
    } success:^{
        //NOTE: turning off gallery image fetching as users are potentially downloading large amounts of data up front when upgrading to a new version of the app.
//        [self fetchGalleryDataForArticle:article failure:failure success:success];
        if (success) {
            success();
        }
    }];
}

- (void)migrateLegacyImagesInArticle:(MWKArticle*)article {
    //  Copies saved article images cached by versions 5.0.4 and older to the locations where 5.0.5 and newer are looking for them. Previously, the app cached at the width of the largest image in the srcset. Currently, we request a thumbnail at wmf_articleImageWidthForScale (or original if it's narrower than that width). By copying from the old size to the new expected sizes, we ensure that articles saved with these older versions will still have images availble offline in the newer versions.
    WMFImageController* imageController = [WMFImageController sharedInstance];
    NSArray* legacyImageURLs            = [self.dataStore legacyImageURLsForArticle:article];
    NSUInteger articleImageWidth        = [[UIScreen mainScreen] wmf_articleImageWidthForScale];
    for (NSURL* legacyImageURL in legacyImageURLs) {
        NSString* legacyImageURLString = legacyImageURL.absoluteString;
        NSUInteger width               = WMFParseSizePrefixFromSourceURL(legacyImageURLString);
        if (width != articleImageWidth && width != NSNotFound) {
            if (legacyImageURL != nil && [imageController hasDataOnDiskForImageWithURL:legacyImageURL]) {
                NSURL* cachedFileURL = [NSURL fileURLWithPath:[imageController cachePathForImageWithURL:legacyImageURL] isDirectory:NO];
                if (cachedFileURL != nil) {
                    NSString* imageExtension = [legacyImageURL pathExtension];
                    NSString* imageMIMEType  = [imageExtension wmf_asMIMEType];

                    NSString* imageURLStringAtArticleWidth = WMFChangeImageSourceURLSizePrefix(legacyImageURLString, articleImageWidth);
                    NSURL* imageURLAtArticleWidth          = [NSURL URLWithString:imageURLStringAtArticleWidth];
                    if (imageURLAtArticleWidth != nil && ![imageController hasDataOnDiskForImageWithURL:imageURLAtArticleWidth]) {
                        [imageController cacheImageFromFileURL:cachedFileURL forURL:imageURLAtArticleWidth MIMEType:imageMIMEType];
                    }

                    NSString* originalImageURLString = WMFOriginalImageURLStringFromURLString(legacyImageURLString);
                    NSURL* originalImageURL          = [NSURL URLWithString:originalImageURLString];
                    if (![imageController hasDataOnDiskForImageWithURL:originalImageURL]) {
                        [imageController cacheImageFromFileURL:cachedFileURL forURL:originalImageURL MIMEType:imageMIMEType];
                    }
                }
            }
        }
    }
}

- (void)fetchAllImagesInArticle:(MWKArticle*)article failure:(WMFErrorHandler)failure success:(WMFSuccessHandler)success {
    if (![[NSUserDefaults standardUserDefaults] wmf_didFinishLegacySavedArticleImageMigration]) {
        WMF_TECH_DEBT_TODO(This legacy migration can be removed after enough users upgrade to 5.0 .5)
        [self migrateLegacyImagesInArticle : article];
    }

    WMFURLCache* cache = (WMFURLCache*)[NSURLCache sharedURLCache];
    [cache permanentlyCacheImagesForArticle:article];

    NSArray<NSURL*>* URLs = [[article allImageURLs] allObjects];
    [self cacheImagesWithURLsInBackground:URLs failure:failure success:success];
}

- (void)fetchGalleryDataForArticle:(MWKArticle*)article failure:(WMFErrorHandler)failure success:(WMFSuccessHandler)success {
    WMF_TECH_DEBT_TODO(check whether on - disk image info matches what we are about to fetch)
    @weakify(self);

    [self fetchImageInfoForImagesInArticle:article failure:^(NSError* error) {
        failure(error);
    } success:^(NSArray* info) {
        @strongify(self);
        if (!self) {
            failure([NSError cancelledError]);
            return;
        }
        if (info.count == 0) {
            DDLogVerbose(@"No gallery images to fetch.");
            success();
            return;
        }

        NSArray* URLs = [info valueForKey:@"imageThumbURL"];
        [self cacheImagesWithURLsInBackground:URLs failure:failure success:success];
    }];
}

- (void)fetchImageInfoForImagesInArticle:(MWKArticle*)article failure:(WMFErrorHandler)failure success:(WMFSuccessNSArrayHandler)success {
    @weakify(self);
    NSArray<NSString*>* imageFileTitles =
        [MWKImage mapFilenamesFromImages:[article imagesForGallery]];

    if (imageFileTitles.count == 0) {
        DDLogVerbose(@"No image info to fetch, returning successful promise with empty array.");
        success(imageFileTitles);
        return;
    }

    for (NSString* canonicalFilename in imageFileTitles) {
        [self.imageInfoFetcher fetchGalleryInfoForImage:canonicalFilename fromSiteURL:article.url];
    }

    PMKJoin([[imageFileTitles bk_map:^AnyPromise*(NSString* canonicalFilename) {
        return [self.imageInfoFetcher fetchGalleryInfoForImage:canonicalFilename fromSiteURL:article.url];
    }] bk_reject:^BOOL (id obj) {
        return [obj isEqual:[NSNull null]];
    }]).thenInBackground(^id (NSArray* infoObjects) {
        @strongify(self);
        if (!self) {
            return [NSError cancelledError];
        }
        [self.dataStore saveImageInfo:infoObjects forArticleURL:article.url];
        success(infoObjects);
        return infoObjects;
    });
}

- (void)cacheImagesWithURLsInBackground:(NSArray<NSURL*>*)imageURLs failure:(void (^ _Nonnull)(NSError* _Nonnull error))failure success:(void (^ _Nonnull)(void))success {
    imageURLs = [imageURLs bk_select:^BOOL (id obj) {
        return [obj isKindOfClass:[NSURL class]];
    }];

    if ([imageURLs count] == 0) {
        success();
        return;
    }

    [self.imageController cacheImagesWithURLsInBackground:imageURLs failure:failure success:success];
}

#pragma mark - Cancellation

- (void)cancelFetchForSavedPages {
    BOOL wasFetching = self.fetchOperationsByArticleTitle.count > 0;
    [self.savedPageList enumerateItemsWithBlock:^(MWKHistoryEntry* _Nonnull entry, BOOL* _Nonnull stop) {
        dispatch_async(self.accessQueue, ^{
            [self cancelFetchForArticleURL:entry.url];
        });
    }];
    if (wasFetching) {
        /*
           only notify delegate if deletion occurs during a download session. if deletion occurs
           after the fact, we don't need to inform delegate of completion
         */
        [self notifyDelegateIfFinished];
    }
}

- (void)cancelFetchForArticleURL:(NSURL*)URL {
    DDLogVerbose(@"Canceling saved page download for title: %@", URL);
    [self.articleFetcher cancelFetchForArticleURL:URL];
    [[[self.dataStore existingArticleWithURL:URL] allImageURLs] bk_each:^(NSURL* imageURL) {
        [self.imageController cancelFetchForURL:imageURL];
    }];
    WMF_TECH_DEBT_TODO(cancel image info & high - res image requests)
    [self.fetchOperationsByArticleTitle removeObjectForKey : URL];
}

#pragma mark - Progress

- (void)getProgress:(WMFProgressHandler)progressBlock {
    dispatch_async(self.accessQueue, ^{
        CGFloat progress = [self progress];

        dispatch_async(dispatch_get_main_queue(), ^{
            progressBlock(progress);
        });
    });
}

/// Only invoke within accessQueue
- (CGFloat)progress {
    /*
       FIXME: Handle progress when only downloading a subset of saved pages (e.g. if some were already downloaded in
       a previous session)?
     */
    if ([self.savedPageList numberOfItems] == 0) {
        return 0.0;
    }

    return (CGFloat)([self.savedPageList numberOfItems] - [self.fetchOperationsByArticleTitle count])
           / (CGFloat)[self.savedPageList numberOfItems];
}

#pragma mark - Delegate Notification

/// Only invoke within accessQueue
- (void)didFetchArticle:(MWKArticle* __nullable)fetchedArticle
                    url:(NSURL*)url
                  error:(NSError* __nullable)error {
    if (error) {
        // store errors for later reporting
        DDLogError(@"Failed to download saved page %@ due to error: %@", url, error);
        self.errorsByArticleTitle[url] = error;
    } else {
        DDLogInfo(@"Downloaded saved page: %@", url);
    }

    // stop tracking operation, effectively advancing the progress
    [self.fetchOperationsByArticleTitle removeObjectForKey:url];

    CGFloat progress = [self progress];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.fetchFinishedDelegate savedArticlesFetcher:self
                                             didFetchURL:url
                                                 article:fetchedArticle
                                                progress:progress
                                                   error:error];
    });

    [self notifyDelegateIfFinished];
}

/// Only invoke within accessQueue
- (void)notifyDelegateIfFinished {
    if ([self.fetchOperationsByArticleTitle count] == 0) {
        NSError* reportedError;
        if ([self.errorsByArticleTitle count] > 0) {
            reportedError = [[self.errorsByArticleTitle allValues] firstObject];
        }

        [self.errorsByArticleTitle removeAllObjects];

        DDLogInfo(@"Finished downloading all saved pages!");

        [self finishWithError:reportedError
                  fetchedData:nil];
    }
}

@end

static NSString* const WMFSavedPageErrorDomain = @"WMFSavedPageErrorDomain";

@implementation NSError (SavedArticlesFetcherErrors)

+ (instancetype)wmf_savedPageImageDownloadError {
    return [NSError errorWithDomain:WMFSavedPageErrorDomain code:1 userInfo:@{
                NSLocalizedDescriptionKey: MWLocalizedString(@"saved-pages-image-download-error", nil)
            }];
}

@end

NS_ASSUME_NONNULL_END
