
#import "WMFSavedArticleTableViewController.h"
#import "PiwikTracker+WMFExtensions.h"
#import "NSString+WMFExtras.h"
#import "NSUserActivity+WMFExtensions.h"

#import "MWKDataStore.h"
#import "MWKUserDataStore.h"
#import "MWKSavedPageList.h"

#import "WMFDatabase+WMFDatabaseViews.h"
#import "WMFDatabaseDataSource.h"
#import "MWKHistoryEntry+WMFDatabaseStorable.h"

#import "MWKArticle.h"
#import "MWKHistoryEntry.h"

#import "WMFSaveButtonController.h"

#import "WMFArticleListTableViewCell.h"
#import "UIView+WMFDefaultNib.h"
#import "UITableViewCell+WMFLayout.h"


@interface WMFSavedArticleTableViewController ()

@property(nonatomic, strong) WMFDatabaseDataSource* dataSource;

@end

@implementation WMFSavedArticleTableViewController

#pragma mark - NSObject

- (void)dealloc {
    [self.database unregisterChangeHandler:self.dataSource];
}

- (void)awakeFromNib {
    [super awakeFromNib];
    self.title = MWLocalizedString(@"saved-title", nil);
}

#pragma mark - Accessors

- (WMFDatabase*)database {
    return self.dataStore.database;
}

- (MWKSavedPageList*)savedPageList {
    return self.dataStore.userDataStore.savedPageList;
}

#pragma mark - UIViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.dataSource = [[WMFDatabaseDataSource alloc] initWithConnection:self.database.articleReferenceReadConnection mappings:[self.database groupsSortedAlphabeticallyMappingsWithViewName:WMFSavedSortedByDateUngroupedView]];
    [self.database registerChangeHandler:self.dataSource];

    [self.tableView registerNib:[WMFArticleListTableViewCell wmf_classNib] forCellReuseIdentifier:[WMFArticleListTableViewCell identifier]];

    self.tableView.estimatedRowHeight = [WMFArticleListTableViewCell estimatedRowHeight];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[PiwikTracker wmf_configuredInstance] wmf_logView:self];
    [NSUserActivity wmf_makeActivityActive:[NSUserActivity wmf_savedPagesViewActivity]];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return [self.dataSource numberOfSections];
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.dataSource numberOfItemsInSection:section];
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
    [[self savedPageList] removeEntryWithURL:[self urlAtIndexPath:indexPath]];
}

- (WMFEmptyViewType)emptyViewType {
    return WMFEmptyViewTypeNoSavedPages;
}

- (NSString*)analyticsContext {
    return @"Saved";
}

- (NSString*)analyticsName {
    return [self analyticsContext];
}

- (BOOL)showsDeleteAllButton {
    return YES;
}

- (NSString*)deleteButtonText {
    return MWLocalizedString(@"saved-clear-all", nil);
}

- (NSString*)deleteAllConfirmationText {
    return MWLocalizedString(@"saved-pages-clear-confirmation-heading", nil);
}

- (NSString*)deleteText {
    return MWLocalizedString(@"saved-pages-clear-delete-all", nil);
}

- (NSString*)deleteCancelText {
    return MWLocalizedString(@"saved-pages-clear-cancel", nil);
}

- (BOOL)canDeleteItemAtIndexPath:(NSIndexPath*)indexPath {
    return YES;
}

- (NSURL*)urlAtIndexPath:(NSIndexPath*)indexPath {
    return [[self.dataSource objectAtIndexPath:indexPath] url];
}

- (void)deleteAll {
    [[self savedPageList] removeAllEntries];
}

- (NSInteger)numberOfItems {
    return [[self savedPageList] numberOfItems];
}

@end
