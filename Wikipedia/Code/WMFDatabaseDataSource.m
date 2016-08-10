

#import "WMFDatabaseDataSource.h"

NS_ASSUME_NONNULL_BEGIN

@interface WMFDatabaseDataSource ()

@property (readwrite, weak, nonatomic) YapDatabaseConnection* connection;

@property (readonly, strong, nonatomic) NSString* viewName;

@property (readwrite, strong, nonatomic) YapDatabaseViewMappings* mappings;

@end

@implementation WMFDatabaseDataSource

@synthesize delegate;

- (instancetype)initWithConnection:(YapDatabaseConnection*)connection mappings:(YapDatabaseViewMappings*)mappings {
    self = [super init];
    if (self) {
        self.connection = connection;
        self.mappings   = mappings;

        [self.connection readWithBlock:^(YapDatabaseReadTransaction* transaction) {
            //HACK: you mush access the view prior to updating the mappins of the view will be in an inconsistent state: see link
            [transaction ext:self.viewName];
            [self.mappings updateWithTransaction:transaction];
        }];
    }
    return self;
}

- (NSString*)viewName {
    return self.mappings.view;
}

#pragma mark - Table/Collection View Methods

- (NSInteger)numberOfItems {
    return [self.mappings numberOfItemsInAllGroups];
}

- (NSInteger)numberOfSections {
    return [self.mappings numberOfSections];
}

- (NSInteger)numberOfItemsInSection:(NSInteger)section {
    return [self.mappings numberOfItemsInSection:section];
}

- (nullable NSString*)titleForSectionIndex:(NSInteger)index {
    NSString* text = [self.mappings groupForSection:index];
    return text;
}

- (nullable id)objectAtIndexPath:(NSIndexPath*)indexPath {
    __block id results = nil;
    [self.connection readWithBlock:^(YapDatabaseReadTransaction* transaction) {
        YapDatabaseViewTransaction* view = [transaction ext:self.viewName];
        results = [view objectAtIndexPath:indexPath withMappings:self.mappings];
    }];
    return results;
}

- (void)processChanges:(NSArray<YapDatabaseViewRowChange*>*)changes onConnection:(YapDatabaseConnection*)connection{
    if(![connection isEqual:self.connection]){
        return;
    }
    if ([self.delegate respondsToSelector:@selector(dataSourceWillBeginUpdates:)]) {
        [self.delegate dataSourceWillBeginUpdates:self];
    }

    NSArray* sectionChanges = nil;
    NSArray* rowChanges     = nil;

    [[self.connection ext:self.viewName] getSectionChanges:&sectionChanges
                                                rowChanges:&rowChanges
                                          forNotifications:(id)changes
                                              withMappings:self.mappings];



    if ([sectionChanges count] == 0 & [rowChanges count] == 0) {
        return;
    }
    for (YapDatabaseViewSectionChange* sectionChange in sectionChanges) {
        switch (sectionChange.type) {
            case YapDatabaseViewChangeDelete:
            {
                if ([self.delegate respondsToSelector:@selector(dataSource:didDeleteSectionsAtIndexes:)]) {
                    [self.delegate dataSource:self didDeleteSectionsAtIndexes:[NSIndexSet indexSetWithIndex:sectionChange.index]];
                }
                break;
            }
            case YapDatabaseViewChangeInsert:
            {
                if ([self.delegate respondsToSelector:@selector(dataSource:didInsertSectionsAtIndexes:)]) {
                    [self.delegate dataSource:self didInsertSectionsAtIndexes:[NSIndexSet indexSetWithIndex:sectionChange.index]];
                }
                break;
            }
            default: {
                //no other possible cases
            }
        }
    }

    for (YapDatabaseViewRowChange* rowChange in rowChanges) {
        switch (rowChange.type) {
            case YapDatabaseViewChangeDelete:
            {
                if ([self.delegate respondsToSelector:@selector(dataSource:didDeleteRowsAtIndexPaths:)]) {
                    [self.delegate dataSource:self didDeleteRowsAtIndexPaths:@[ rowChange.indexPath ]];
                }
                break;
            }
            case YapDatabaseViewChangeInsert:
            {
                if ([self.delegate respondsToSelector:@selector(dataSource:didInsertRowsAtIndexPaths:)]) {
                    [self.delegate dataSource:self didInsertRowsAtIndexPaths:@[ rowChange.newIndexPath ]];
                }
                break;
            }
            case YapDatabaseViewChangeMove:
            {
                if ([self.delegate respondsToSelector:@selector(dataSource:didMoveRowFromIndexPath:toIndexPath:)]) {
                    [self.delegate dataSource:self didMoveRowFromIndexPath:rowChange.indexPath toIndexPath:rowChange.newIndexPath];
                }
                break;
            }
            case YapDatabaseViewChangeUpdate:
            {
                if ([self.delegate respondsToSelector:@selector(dataSource:didUpdateRowsAtIndexPaths:)]) {
                    [self.delegate dataSource:self didUpdateRowsAtIndexPaths:@[ rowChange.indexPath ]];
                }
                break;
            }
        }
    }

    if ([self.delegate respondsToSelector:@selector(dataSourceDidFinishUpdates:)]) {
        [self.delegate dataSourceDidFinishUpdates:self];
    }
}

@end

NS_ASSUME_NONNULL_END
