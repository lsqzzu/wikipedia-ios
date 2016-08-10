
#import "WMFDatabase+WMFDatabaseViews.h"
#import "MWKHistoryEntry+WMFDatabaseStorable.h"
#import "NSDate+Utilities.h"

@implementation WMFDatabase (WMFDatabaseViews)

- (void)registerViews {
    YapDatabaseViewGrouping* grouping = [self historyGroupingUngrouped];
    YapDatabaseViewSorting* sorting   = [self historySortedByDateDecending];
    YapDatabaseView* databaseView     = [[YapDatabaseView alloc] initWithGrouping:grouping sorting:sorting];
    [self registerView:databaseView withName:WMFHistorySortedByDateUngroupedView];
    
    grouping = [self historyGroupingByDate];
    sorting = [self historySortedByDateDecending];
    databaseView     = [[YapDatabaseView alloc] initWithGrouping:grouping sorting:sorting];
    [self registerView:databaseView withName:WMFHistorySortedByDateGroupedByDateView];

    grouping = [self savedGroupingUngrouped];
    sorting = [self savedSortedByDateDecending];
    databaseView     = [[YapDatabaseView alloc] initWithGrouping:grouping sorting:sorting];
    [self registerView:databaseView withName:WMFSavedSortedByDateUngroupedView];

    grouping = [self historyGroupingUngrouped];
    sorting   = [self historyOrSavedSortedByURL];
    databaseView     = [[YapDatabaseView alloc] initWithGrouping:grouping sorting:sorting];
    [self registerView:databaseView withName:WMFHistoryOrSavedSortedByURLUngroupedView];

    grouping = [self notInHistorySavedOrBlackListGroupingUngrouped];
    sorting   = [self historyOrSavedSortedByURL];
    databaseView     = [[YapDatabaseView alloc] initWithGrouping:grouping sorting:sorting];
    [self registerView:databaseView withName:WMFNotInHistorySavedOrBlackListSortedByURLUngroupedView];
    
    YapDatabaseViewFiltering* filtering = [self historyOrSavedSignificantlyViewedAndNotBlacklistedAndNotMainPageFilter];
    YapDatabaseFilteredView* filteredView =
    [[YapDatabaseFilteredView alloc] initWithParentViewName:WMFHistoryOrSavedSortedByURLUngroupedView filtering:filtering versionTag:@"0"];
    [self registerView:filteredView withName:WMFHistoryOrSavedSortedByURLUngroupedFilteredBySignificnatlyViewedAndNotBlacklistedAndNotMainPageView];
    
}

- (YapDatabaseViewGrouping*)historyGroupingUngrouped {
    return [YapDatabaseViewGrouping withObjectBlock:^NSString* _Nullable (YapDatabaseReadTransaction* _Nonnull transaction, NSString* _Nonnull collection, NSString* _Nonnull key, MWKHistoryEntry* _Nonnull object) {
        if (![collection isEqualToString:[MWKHistoryEntry databaseCollectionName]]) {
            return nil;
        }
        if (object.dateViewed == nil) {
            return nil;
        }
        return @"";
    }];
}

- (YapDatabaseViewGrouping*)savedGroupingUngrouped{
    return [YapDatabaseViewGrouping withObjectBlock:^NSString* _Nullable (YapDatabaseReadTransaction* _Nonnull transaction, NSString* _Nonnull collection, NSString* _Nonnull key, MWKHistoryEntry* _Nonnull object) {
        if (![collection isEqualToString:[MWKHistoryEntry databaseCollectionName]]) {
            return nil;
        }
        if (object.dateSaved == nil) {
            return nil;
        }
        return @"";
    }];
}

- (YapDatabaseViewGrouping*)historyOrSavedGroupingUngrouped{
    return [YapDatabaseViewGrouping withObjectBlock:^NSString* _Nullable (YapDatabaseReadTransaction* _Nonnull transaction, NSString* _Nonnull collection, NSString* _Nonnull key, MWKHistoryEntry* _Nonnull object) {
        if (![collection isEqualToString:[MWKHistoryEntry databaseCollectionName]]) {
            return nil;
        }
        if (object.dateViewed == nil && object.dateSaved == nil) {
            return nil;
        }
        return @"";
    }];
}


- (YapDatabaseViewGrouping*)historyGroupingByDate {
    return [YapDatabaseViewGrouping withObjectBlock:^NSString* _Nullable (YapDatabaseReadTransaction* _Nonnull transaction, NSString* _Nonnull collection, NSString* _Nonnull key, MWKHistoryEntry* _Nonnull object) {
        if (![collection isEqualToString:[MWKHistoryEntry databaseCollectionName]]) {
            return nil;
        }
        if (object.dateViewed == nil) {
            return nil;
        }
        NSDate* date = [[object dateViewed] dateAtStartOfDay];
        return [NSString stringWithFormat:@"%f", [date timeIntervalSince1970]];
    }];
}

- (YapDatabaseViewGrouping*)notInHistorySavedOrBlackListGroupingUngrouped{
    return [YapDatabaseViewGrouping withObjectBlock:^NSString* _Nullable (YapDatabaseReadTransaction* _Nonnull transaction, NSString* _Nonnull collection, NSString* _Nonnull key, MWKHistoryEntry* _Nonnull object) {
        if (![collection isEqualToString:[MWKHistoryEntry databaseCollectionName]]) {
            return nil;
        }
        if (object.dateViewed == nil && object.dateSaved == nil && object.blackListed == NO) {
            return @"";
        }else{
            return nil;
        }
    }];
}


- (YapDatabaseViewSorting*)historySortedByDateDecending {
    return [YapDatabaseViewSorting withObjectBlock:^NSComparisonResult (YapDatabaseReadTransaction* _Nonnull transaction, NSString* _Nonnull group, NSString* _Nonnull collection1, NSString* _Nonnull key1, MWKHistoryEntry* _Nonnull object1, NSString* _Nonnull collection2, NSString* _Nonnull key2, MWKHistoryEntry* _Nonnull object2) {
        return -[object1.dateViewed compare:object2.dateViewed];
    }];
}

- (YapDatabaseViewSorting*)savedSortedByDateDecending{
    return [YapDatabaseViewSorting withObjectBlock:^NSComparisonResult (YapDatabaseReadTransaction* _Nonnull transaction, NSString* _Nonnull group, NSString* _Nonnull collection1, NSString* _Nonnull key1, MWKHistoryEntry* _Nonnull object1, NSString* _Nonnull collection2, NSString* _Nonnull key2, MWKHistoryEntry* _Nonnull object2) {
        return -[object1.dateSaved compare:object2.dateSaved];
    }];
}

- (YapDatabaseViewSorting*)historyOrSavedSortedByURL{
    return [YapDatabaseViewSorting withKeyBlock:^NSComparisonResult(YapDatabaseReadTransaction * _Nonnull transaction, NSString * _Nonnull group, NSString * _Nonnull collection1, NSString * _Nonnull key1, NSString * _Nonnull collection2, NSString * _Nonnull key2) {
        return [key1 compare:key2];
    }];
}


- (YapDatabaseViewFiltering*)historyOrSavedSignificantlyViewedAndNotBlacklistedAndNotMainPageFilter{
    return [YapDatabaseViewFiltering withObjectBlock:^BOOL (YapDatabaseReadTransaction* _Nonnull transaction, NSString* _Nonnull group, NSString* _Nonnull collection, NSString* _Nonnull key, MWKHistoryEntry* _Nonnull object) {
        return [object titleWasSignificantlyViewed] && ![object isBlackListed] && ![[object url] wmf_isMainPage];
    }];
}

- (YapDatabaseViewFiltering*)excludedKeysFilter:(NSArray<NSString*>*)keysToExclude{
    return [YapDatabaseViewFiltering withKeyBlock:^BOOL(YapDatabaseReadTransaction * _Nonnull transaction, NSString * _Nonnull group, NSString * _Nonnull collection, NSString * _Nonnull key) {
        return ![keysToExclude containsObject:key];
    }];
}


NSString* const WMFHistorySortedByDateGroupedByDateView = @"WMFHistorySortedByDateGroupedByDateView";
NSString* const WMFHistorySortedByDateUngroupedView = @"WMFHistorySortedByDateUngroupedView";
NSString* const WMFSavedSortedByDateUngroupedView = @"WMFSavedSortedByDateUngroupedView";
NSString* const WMFHistoryOrSavedSortedByURLUngroupedView = @"WMFHistoryOrSavedSortedByURLUngroupedView";
NSString* const WMFHistoryOrSavedSortedByURLUngroupedFilteredBySignificnatlyViewedAndNotBlacklistedAndNotMainPageView = @"WMFHistoryOrSavedSortedByURLUngroupedFilteredBySignificnatlyViewedAndNotBlacklistedAndNotMainPageView";
NSString* const WMFNotInHistorySavedOrBlackListSortedByURLUngroupedView = @"WMFNotInHistorySavedOrBlackListSortedByURLUngroupedView";


- (YapDatabaseViewMappings*)historyGroupsSortedByDateDecendingMappings {
    return [[YapDatabaseViewMappings alloc] initWithGroupFilterBlock:^BOOL (NSString* _Nonnull group, YapDatabaseReadTransaction* _Nonnull transaction) {
        return YES;
    } sortBlock:^NSComparisonResult (NSString* _Nonnull group1, NSString* _Nonnull group2, YapDatabaseReadTransaction* _Nonnull transaction) {
        if ([group1 doubleValue] < [group2 doubleValue]) {
            return NSOrderedDescending;
        } else if ([group1 doubleValue] > [group2 doubleValue]) {
            return NSOrderedAscending;
        } else {
            return NSOrderedSame;
        }
    } view:WMFHistorySortedByDateGroupedByDateView];
}

- (YapDatabaseViewMappings*)groupsSortedAlphabeticallyMappingsWithViewName:(NSString*)viewName{
    return [[YapDatabaseViewMappings alloc] initWithGroupFilterBlock:^BOOL (NSString* _Nonnull group, YapDatabaseReadTransaction* _Nonnull transaction) {
        return YES;
    } sortBlock:^NSComparisonResult (NSString* _Nonnull group1, NSString* _Nonnull group2, YapDatabaseReadTransaction* _Nonnull transaction) {
        return [group1 localizedCaseInsensitiveCompare:group2];
    } view:viewName];
}


@end
