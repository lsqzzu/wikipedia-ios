
#import "MWKHistoryList.h"
#import "MWKDataStore.h"
#import "WMFDatabase+WMFDatabaseViews.h"
#import "YapDatabaseConnection+WMFExtensions.h"
#import "NSDateFormatter+WMFExtensions.h"
#import "MWKHistoryEntry+WMFDatabaseStorable.h"
#import "Wikipedia-Swift.h"


#define MAX_HISTORY_ENTRIES 100

NS_ASSUME_NONNULL_BEGIN

@interface MWKHistoryList ()

@property (readwrite, weak, nonatomic) WMFDatabase* database;

@property (readwrite, strong, nonatomic) YapDatabaseConnection* writeConnection;

@property (readwrite, weak, nonatomic) MWKDataStore* dataStore;

@end

@implementation MWKHistoryList

#pragma mark - Setup

- (instancetype)initWithDatabase:(WMFDatabase*)database {
    self = [self initWithDatabase:database migrateDataFromLegacyStore:nil];
    return self;
}

- (instancetype)initWithDatabase:(WMFDatabase*)database migrateDataFromLegacyStore:(nullable MWKDataStore*)dataStore {
    NSParameterAssert(database);
    self = [super init];
    if (self) {
        self.dataStore       = dataStore;
        self.database        = database;
        self.writeConnection = [self.database newWriteConnection];
        [self migrateLegacyDataIfNeeded];
    }
    return self;
}

#pragma mark - Legacy Migration

- (void)migrateLegacyDataIfNeeded {
    if ([[NSUserDefaults standardUserDefaults] wmf_didMigrateHistoryList]) {
        return;
    }

    NSArray<MWKHistoryEntry*>* entries = [[self.dataStore historyListData] wmf_mapAndRejectNil:^id (id obj) {
        @try {
            return [[MWKHistoryEntry alloc] initWithDict:obj];
        } @catch (NSException* exception) {
            return nil;
        }
    }];

    if ([entries count] > 0) {
        YapDatabaseConnection* connection = [self.database newWriteConnection];

        [connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction* _Nonnull transaction) {
            [entries enumerateObjectsUsingBlock:^(MWKHistoryEntry* _Nonnull obj, NSUInteger idx, BOOL* _Nonnull stop) {
                MWKHistoryEntry* existing = [transaction objectForKey:[obj databaseKey] inCollection:[MWKHistoryEntry databaseCollectionName]];
                if (existing) {
                    obj.dateSaved = existing.dateSaved;
                    obj.blackListed = existing.isBlackListed;
                }

                [transaction setObject:obj forKey:[obj databaseKey] inCollection:[MWKHistoryEntry databaseCollectionName]];
            }];
        }];

        [[NSUserDefaults standardUserDefaults] wmf_setDidMigrateHistoryList:YES];

#warning remove legacy data?
#warning handle any errors
    }
}

#pragma mark - Entry Access

- (nullable id)readAndReturnResultsWithBlock:(id (^)(YapDatabaseReadTransaction* _Nonnull transaction, YapDatabaseViewTransaction* _Nonnull view))block {
    return [self.database.articleReferenceReadConnection wmf_readAndReturnResultsInViewWithName:WMFHistorySortedByDateUngroupedView withBlock:block];
}

#pragma mark - Convienence Methods

- (NSInteger)numberOfItems {
    return [[self readAndReturnResultsWithBlock:^id _Nonnull (YapDatabaseReadTransaction* _Nonnull transaction, YapDatabaseViewTransaction* _Nonnull view) {
        return @([view numberOfItemsInAllGroups]);
    }] integerValue];
}

- (nullable MWKHistoryEntry*)mostRecentEntry {
    return [self readAndReturnResultsWithBlock:^id _Nonnull (YapDatabaseReadTransaction* _Nonnull transaction, YapDatabaseViewTransaction* _Nonnull view) {
        return [view objectAtIndex:0 inGroup:[[view allGroups] firstObject]];
    }];
}

- (nullable MWKHistoryEntry*)entryForURL:(NSURL*)url {
    return [self readAndReturnResultsWithBlock:^id _Nonnull (YapDatabaseReadTransaction* _Nonnull transaction, YapDatabaseViewTransaction* _Nonnull view) {
        return [transaction objectForKey:[MWKHistoryEntry databaseKeyForURL:url] inCollection:[MWKHistoryEntry databaseCollectionName]];
    }];
}

#pragma mark - Update Methods

- (MWKHistoryEntry*)addPageToHistoryWithURL:(NSURL*)url {
    NSParameterAssert(url);
    if ([url wmf_isNonStandardURL]) {
        return nil;
    }
    if ([url.wmf_title length] == 0) {
        return nil;
    }

    __block MWKHistoryEntry* entry = nil;

    [self.writeConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction* _Nonnull transaction) {
        entry = [transaction objectForKey:[MWKHistoryEntry databaseKeyForURL:url] inCollection:[MWKHistoryEntry databaseCollectionName]];
        if (!entry) {
            entry = [[MWKHistoryEntry alloc] initWithURL:url];
        }
        entry.dateViewed = [NSDate date];

        [transaction setObject:entry forKey:[MWKHistoryEntry databaseKeyForURL:url] inCollection:[MWKHistoryEntry databaseCollectionName]];
    }];

    return entry;
}

- (void)setPageScrollPosition:(CGFloat)scrollposition onPageInHistoryWithURL:(NSURL*)url {
    if ([url.wmf_title length] == 0) {
        return;
    }

    [self.writeConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction* _Nonnull transaction) {
        MWKHistoryEntry* entry = [transaction objectForKey:[MWKHistoryEntry databaseKeyForURL:url] inCollection:[MWKHistoryEntry databaseCollectionName]];
        if (entry) {
            entry.scrollPosition = scrollposition;
            [transaction setObject:entry forKey:[MWKHistoryEntry databaseKeyForURL:url] inCollection:[MWKHistoryEntry databaseCollectionName]];
        }
    }];
}

- (void)setSignificantlyViewedOnPageInHistoryWithURL:(NSURL*)url {
    if ([url.wmf_title length] == 0) {
        return;
    }
    [self.writeConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction* _Nonnull transaction) {
        MWKHistoryEntry* entry = [transaction objectForKey:[MWKHistoryEntry databaseKeyForURL:url] inCollection:[MWKHistoryEntry databaseCollectionName]];
        if (entry) {
            entry.titleWasSignificantlyViewed = YES;
            [transaction setObject:entry forKey:[MWKHistoryEntry databaseKeyForURL:url] inCollection:[MWKHistoryEntry databaseCollectionName]];
        }
    }];
}

- (void)removeEntryWithURL:(NSURL*)url {
    if ([[url wmf_title] length] == 0) {
        return;
    }
    [self.writeConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction* _Nonnull transaction) {
        MWKHistoryEntry* entry = [transaction objectForKey:[MWKHistoryEntry databaseKeyForURL:url] inCollection:[MWKHistoryEntry databaseCollectionName]];
        entry.dateViewed = nil;
        [transaction setObject:entry forKey:[MWKHistoryEntry databaseKeyForURL:url] inCollection:[MWKHistoryEntry databaseCollectionName]];
    }];
}

- (void)removeAllEntries {
    [self.writeConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction* _Nonnull transaction) {
        [transaction enumerateKeysAndObjectsInCollection:[MWKHistoryEntry databaseCollectionName] usingBlock:^(NSString* _Nonnull key, MWKHistoryEntry* _Nonnull object, BOOL* _Nonnull stop) {
            object.dateViewed = nil;
            [transaction setObject:object forKey:key inCollection:[MWKHistoryEntry databaseCollectionName]];
        }];
    }];
}

@end

NS_ASSUME_NONNULL_END
