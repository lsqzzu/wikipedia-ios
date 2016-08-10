
#import "WMFHistoryTableViewController.h"
#import "PiwikTracker+WMFExtensions.h"
#import "NSUserActivity+WMFExtensions.h"

#import "NSString+WMFExtras.h"
#import "NSDateFormatter+WMFExtensions.h"
#import "NSDate+Utilities.h"

#import "MWKDataStore.h"
#import "MWKHistoryList.h"
#import "MWKUserDataStore.h"

#import "WMFDatabase+WMFDatabaseViews.h"
#import "WMFDatabaseDataSource.h"
#import "MWKHistoryEntry+WMFDatabaseStorable.h"

#import "MWKArticle.h"
#import "MWKSavedPageEntry.h"

#import "WMFArticleListTableViewCell.h"
#import "UIView+WMFDefaultNib.h"
#import "UITableViewCell+WMFLayout.h"


@interface WMFHistoryTableViewController ()

@property(nonatomic, strong) WMFDatabaseDataSource* dataSource;

@end

@implementation WMFHistoryTableViewController

#pragma mark - NSObject

- (void)dealloc {
    [self.database unregisterChangeHandler:self.dataSource];
}

- (void)awakeFromNib {
    [super awakeFromNib];
    self.title = MWLocalizedString(@"history-title", nil);
}

#pragma mark - Accessors

- (WMFDatabase*)database {
    return self.dataStore.database;
}

- (MWKHistoryList*)historyList {
    return self.dataStore.userDataStore.historyList;
}

- (MWKSavedPageList*)savedPageList {
    return self.dataStore.userDataStore.savedPageList;
}

#pragma mark - UIViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.dataSource = [[WMFDatabaseDataSource alloc] initWithConnection:self.database.articleReferenceReadConnection mappings:[self.database historyGroupsSortedByDateDecendingMappings]];
    [self.database registerChangeHandler:self.dataSource];

    [self.tableView registerNib:[WMFArticleListTableViewCell wmf_classNib] forCellReuseIdentifier:[WMFArticleListTableViewCell identifier]];

    self.tableView.estimatedRowHeight = [WMFArticleListTableViewCell estimatedRowHeight];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[PiwikTracker wmf_configuredInstance] wmf_logView:self];
    [NSUserActivity wmf_makeActivityActive:[NSUserActivity wmf_recentViewActivity]];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return [self.dataSource numberOfSections];
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.dataSource numberOfItemsInSection:section];
}

- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section {
    NSString* dateString = [self.dataSource titleForSectionIndex:section];
    NSDate* date         = [NSDate dateWithTimeIntervalSince1970:[dateString doubleValue]];

    //HACK: Table views for some reason aren't adding padding to the left of the default headers. Injecting some manually.
    NSString* padding = @"    ";

    if ([date isToday]) {
        return [padding stringByAppendingString:[MWLocalizedString(@"history-section-today", nil) uppercaseString]];
    } else if ([date isYesterday]) {
        return [padding stringByAppendingString:[MWLocalizedString(@"history-section-yesterday", nil) uppercaseString]];
    } else {
        return [padding stringByAppendingString:[[NSDateFormatter wmf_mediumDateFormatterWithoutTime] stringFromDate:date]];
    }
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    WMFArticleListTableViewCell* cell = [self.tableView dequeueReusableCellWithIdentifier:[WMFArticleListTableViewCell identifier] forIndexPath:indexPath];

    MWKHistoryEntry* entry = [self.dataSource objectAtIndexPath:indexPath];
    MWKArticle* article    = [[self dataStore] articleWithURL:entry.url];
    cell.titleText       = article.url.wmf_title;
    cell.descriptionText = [article.entityDescription wmf_stringByCapitalizingFirstCharacter];
    [cell setImage:[article bestThumbnailImage]];

    return cell;
}

- (UITableViewCellEditingStyle)tableView:(UITableView*)tableView editingStyleForRowAtIndexPath:(NSIndexPath*)indexPath {
    return YES;
}

- (void)tableView:(UITableView*)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath*)indexPath {
    [[self historyList] removeEntryWithURL:[self urlAtIndexPath:indexPath]];
}

#pragma mark - WMFArticleListTableViewController

- (WMFEmptyViewType)emptyViewType {
    return WMFEmptyViewTypeNoHistory;
}

- (NSString*)analyticsContext {
    return @"Recent";
}

- (NSString*)analyticsName {
    return [self analyticsContext];
}

- (BOOL)showsDeleteAllButton {
    return YES;
}

- (NSString*)deleteButtonText {
    return MWLocalizedString(@"history-clear-all", nil);
}

- (NSString*)deleteAllConfirmationText {
    return MWLocalizedString(@"history-clear-confirmation-heading", nil);
}

- (NSString*)deleteText {
    return MWLocalizedString(@"history-clear-delete-all", nil);
}

- (NSString*)deleteCancelText {
    return MWLocalizedString(@"history-clear-cancel", nil);
}

- (BOOL)canDeleteItemAtIndexPath:(NSIndexPath*)indexPath {
    return YES;
}

- (NSURL*)urlAtIndexPath:(NSIndexPath*)indexPath {
    return [[self.dataSource objectAtIndexPath:indexPath] url];
}

- (void)deleteAll {
    [[self historyList] removeAllEntries];
}

- (NSInteger)numberOfItems {
    return [[self historyList] numberOfItems];
}

@end
