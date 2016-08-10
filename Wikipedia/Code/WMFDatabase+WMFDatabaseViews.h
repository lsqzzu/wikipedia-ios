
#import "WMFDatabase.h"

@interface WMFDatabase (WMFDatabaseViews)

#pragma mark - View Components
/**
 *  The following components can be combined to create views in the database.
 *
 *  Views are constructed using a YapDatabaseViewGrouping and a YapDatabaseViewSorting object.
 *  Existing views can be filtered applying a YapDatabaseViewFiltering
 *
 *  Once registered, views can be referenced by their view name on a specific connection.
 */


- (YapDatabaseViewGrouping*)historyGroupingUngrouped;
- (YapDatabaseViewGrouping*)savedGroupingUngrouped;
- (YapDatabaseViewGrouping*)historyOrSavedGroupingUngrouped;
- (YapDatabaseViewGrouping*)historyGroupingByDate;
- (YapDatabaseViewGrouping*)notInHistorySavedOrBlackListGroupingUngrouped;

- (YapDatabaseViewSorting*)historySortedByDateDecending;
- (YapDatabaseViewSorting*)savedSortedByDateDecending;
- (YapDatabaseViewSorting*)historyOrSavedSortedByURL;

- (YapDatabaseViewFiltering*)historyOrSavedSignificantlyViewedAndNotBlacklistedAndNotMainPageFilter;
- (YapDatabaseViewFiltering*)excludedKeysFilter:(NSArray<NSString*>*)keysToExclude;


#pragma mark - Registered View Names
/**
 *  Views are given a name when registered in the DB
 *  It is reccomended that all view names be documented here to:
 *
 *  1. Make them public so others can reference them
 *  2. Make sure the names are not duplicated (view names must be unique)
 */


/**
 *  historyOrSavedGroupingUngrouped + historySortedByDateDecending
 */
extern NSString* const WMFHistorySortedByDateGroupedByDateView;

/**
 *  historyGroupingUngrouped + historySortedByDateDecending
 */
extern NSString* const WMFHistorySortedByDateUngroupedView;

/**
 *  savedGroupingUngrouped + savedSortedByDateDecending
 */
extern NSString* const WMFSavedSortedByDateUngroupedView;

/**
 *  historyOrSavedGroupingUngrouped + historyOrSavedSortedByURL
 */
extern NSString* const WMFHistoryOrSavedSortedByURLUngroupedView;

/**
 *  historyOrSavedSignificantlyViewedAndNotBlacklistedAndNotMainPageFilter + WMFHistoryOrSavedSortedByURLUngroupedView
 */
extern NSString* const WMFHistoryOrSavedSortedByURLUngroupedFilteredBySignificnatlyViewedAndNotBlacklistedAndNotMainPageView;

/**
 *  notInHistorySavedOrBlackListGroupingUngrouped + historyOrSavedSortedByURL
 */
extern NSString* const WMFNotInHistorySavedOrBlackListSortedByURLUngroupedView;

/**
 *  Register the views with the names included above.
 *  If you create a new peristent view, you should register it within this method.
 */
- (void)registerViews;

#pragma mark - Mappings
/**
 *  Mappings are used to sort groups in to sections fit for collection views / table views
 *  Mappings are required for views with mutliple sections that must be displayed in a collection view or table view. They are not for views with a single section.
 *
 *  Although mappings are seperate objects, they are explicitly tied to a view on a instantiation
 */

/**
 *  Sort group names that are Stringified NSTimeIntervals in decending order
 *  This mapping applies only to the WMFHistorySortedByDateGroupedByDateView
 *
 *  @return The mappings
 */
- (YapDatabaseViewMappings*)historyGroupsSortedByDateDecendingMappings;


/**
 *  Sort group names alphabetically
 *
 *  @param viewName The view to apply mappings to
 *
 *  @return The mappings
 */
- (YapDatabaseViewMappings*)groupsSortedAlphabeticallyMappingsWithViewName:(NSString*)viewName;

@end
