#import "MWKSavedPageList.h"
#import "MWKDataStore.h"
#import "WMFDatabase+WMFDatabaseViews.h"
#import "YapDatabaseConnection+WMFExtensions.h"
#import "MWKHistoryEntry+WMFDatabaseStorable.h"
#import "Wikipedia-Swift.h"

//Legacy
#import "MWKSavedPageListDataExportConstants.h"
#import "MWKSavedPageEntry.h"


NSString* const MWKSavedPageListDidSaveNotification   = @"MWKSavedPageListDidSaveNotification";
NSString* const MWKSavedPageListDidUnsaveNotification = @"MWKSavedPageListDidUnsaveNotification";

NSString* const MWKURLKey = @"MWKURLKey";

NSString* const MWKSavedPageExportedEntriesKey       = @"entries";
NSString* const MWKSavedPageExportedSchemaVersionKey = @"schemaVersion";

@interface MWKSavedPageList ()

@property (readwrite, weak, nonatomic) WMFDatabase* database;

@property (readwrite, strong, nonatomic) YapDatabaseConnection* writeConnection;

@property (readwrite, weak, nonatomic) MWKDataStore* dataStore;

@end

@implementation MWKSavedPageList

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

- (MWKHistoryEntry*)historyEntryWithSavedPageEntry:(MWKSavedPageEntry*)entry {
    MWKHistoryEntry* history = [[MWKHistoryEntry alloc] initWithURL:entry.url];
    history.dateSaved = entry.date;
    return history;
}

- (void)migrateLegacyDataIfNeeded {
    if ([[NSUserDefaults standardUserDefaults] wmf_didMigrateSavedPageList]) {
        return;
    }

    NSArray<MWKSavedPageEntry*>* entries =
        [[MWKSavedPageList savedEntryDataFromExportedData:[self.dataStore savedPageListData]] wmf_mapAndRejectNil:^id (id obj) {
        @try {
            return [[MWKSavedPageEntry alloc] initWithDict:obj];
        } @catch (NSException* e) {
            return nil;
        }
    }];

    if ([entries count] > 0) {
        YapDatabaseConnection* connection = [self.database newWriteConnection];

        [connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction* _Nonnull transaction) {
            [entries enumerateObjectsUsingBlock:^(MWKSavedPageEntry* _Nonnull obj, NSUInteger idx, BOOL* _Nonnull stop) {
                if (obj.url.wmf_title.length == 0) {
                    //Added check from existing logic. Apparently there was a time when this URL could be bad. Copying here to keep exisitng functionality
                    return;
                }
                MWKHistoryEntry* history = [self historyEntryWithSavedPageEntry:obj];
                MWKHistoryEntry* existing = [transaction objectForKey:[history databaseKey] inCollection:[MWKHistoryEntry databaseCollectionName]];
                if (existing) {
                    existing.dateSaved = history.dateSaved;
                    history = existing;
                }
                [transaction setObject:history forKey:[history databaseKey] inCollection:[MWKHistoryEntry databaseCollectionName]];
            }];
        }];

        [[NSUserDefaults standardUserDefaults] wmf_setDidMigrateSavedPageList:YES];

#warning remove legacy data?
#warning handle any errors
    }
}

#pragma mark - Entry Access

- (nullable id)readAndReturnResultsWithBlock:(id (^)(YapDatabaseReadTransaction* _Nonnull transaction, YapDatabaseViewTransaction* _Nonnull view))block {
    return [self.database.articleReferenceReadConnection wmf_readAndReturnResultsInViewWithName:WMFSavedSortedByDateUngroupedView withBlock:block];
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
        MWKHistoryEntry* entry = [transaction objectForKey:[MWKHistoryEntry databaseKeyForURL:url] inCollection:[MWKHistoryEntry databaseCollectionName]];
        return entry;
    }];
}

- (void)enumerateItemsWithBlock:(void (^)(MWKHistoryEntry* _Nonnull entry, BOOL* stop))block {
    if (!block) {
        return;
    }
    [self.database.articleReferenceReadConnection readWithBlock:^(YapDatabaseReadTransaction* _Nonnull transaction) {
        YapDatabaseViewTransaction* view = [transaction ext:WMFSavedSortedByDateUngroupedView];
        if ([view numberOfItemsInAllGroups] == 0) {
            return;
        }
        [view enumerateKeysAndObjectsInGroup:[[view allGroups] firstObject] usingBlock:^(NSString* _Nonnull collection, NSString* _Nonnull key, id _Nonnull object, NSUInteger index, BOOL* _Nonnull stop) {
            block(object, stop);
        }];
    }];
}

- (BOOL)isSaved:(NSURL*)url {
    if ([url.wmf_title length] == 0) {
        return NO;
    }
    return [self entryForURL:url].dateSaved != nil;
}

#pragma mark - Update Methods

- (void)toggleSavedPageForURL:(NSURL*)url {
    if ([self isSaved:url]) {
        [self removeEntryWithURL:url];
    } else {
        [self addSavedPageWithURL:url];
    }
}

- (MWKHistoryEntry*)addSavedPageWithURL:(NSURL*)url {
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
        if(!entry.dateSaved){
            entry.dateSaved = [NSDate date];
        }

        [transaction setObject:entry forKey:[MWKHistoryEntry databaseKeyForURL:url] inCollection:[MWKHistoryEntry databaseCollectionName]];
    }];

    [[NSNotificationCenter defaultCenter] postNotificationName:MWKSavedPageListDidSaveNotification object:self userInfo:@{MWKURLKey: entry.url}];

    return entry;
}

- (void)removeEntryWithURL:(NSURL*)url {
    if ([url.wmf_title length] == 0) {
        return;
    }
    [self.writeConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction* _Nonnull transaction) {
        MWKHistoryEntry* entry = [transaction objectForKey:[MWKHistoryEntry databaseKeyForURL:url] inCollection:[MWKHistoryEntry databaseCollectionName]];
        entry.dateSaved = nil;
        [transaction setObject:entry forKey:[MWKHistoryEntry databaseKeyForURL:url] inCollection:[MWKHistoryEntry databaseCollectionName]];
    }];

    [[NSNotificationCenter defaultCenter] postNotificationName:MWKSavedPageListDidUnsaveNotification object:self userInfo:@{MWKURLKey: url}];
}

- (void)removeAllEntries {
    [self.writeConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction* _Nonnull transaction) {
        [transaction enumerateKeysAndObjectsInCollection:[MWKHistoryEntry databaseCollectionName] usingBlock:^(NSString* _Nonnull key, MWKHistoryEntry* _Nonnull object, BOOL* _Nonnull stop) {
            object.dateSaved = nil;
            [transaction setObject:object forKey:key inCollection:[MWKHistoryEntry databaseCollectionName]];
        }];
    }];
}

#pragma mark - Legacy Schema Migration

+ (NSArray<NSDictionary*>*)savedEntryDataFromExportedData:(NSDictionary*)savedPageListData {
    NSNumber* schemaVersionValue                = savedPageListData[MWKSavedPageExportedSchemaVersionKey];
    MWKSavedPageListSchemaVersion schemaVersion = MWKSavedPageListSchemaVersionUnknown;
    if (schemaVersionValue) {
        schemaVersion = schemaVersionValue.unsignedIntegerValue;
    }
    switch (schemaVersion) {
        case MWKSavedPageListSchemaVersionCurrent:
            return savedPageListData[MWKSavedPageExportedEntriesKey];
        case MWKSavedPageListSchemaVersionUnknown:
            return [MWKSavedPageList savedEntryDataFromListWithUnknownSchema:savedPageListData];
    }
}

+ (NSArray<NSDictionary*>*)savedEntryDataFromListWithUnknownSchema:(NSDictionary*)data {
    return [data[MWKSavedPageExportedEntriesKey] wmf_reverseArray];
}

#pragma mark - Export

@end
