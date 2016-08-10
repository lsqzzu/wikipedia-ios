
#import "YapDatabaseConnection+WMFExtensions.h"

NS_ASSUME_NONNULL_BEGIN

@implementation YapDatabaseConnection (WMFExtensions)

- (nullable id)wmf_readAndReturnResultsInViewWithName:(NSString*)viewName withBlock:(id (^)(YapDatabaseReadTransaction* _Nonnull transaction, YapDatabaseViewTransaction* _Nonnull view))block {
    __block id results = nil;
    NSParameterAssert(block);
    [self readWithBlock:^(YapDatabaseReadTransaction* _Nonnull transaction) {
        YapDatabaseViewTransaction* view = [transaction ext:viewName];
        NSParameterAssert(view);
        results = block(transaction, view);
    }];
    
    return results;
}

@end

NS_ASSUME_NONNULL_END
