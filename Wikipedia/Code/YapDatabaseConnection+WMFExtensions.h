

#import <YapDatabase/YapDatabase.h>
#import <YapDataBase/YapDatabaseView.h>

NS_ASSUME_NONNULL_BEGIN

@interface YapDatabaseConnection (WMFExtensions)

- (nullable id)wmf_readAndReturnResultsInViewWithName:(NSString*)viewName withBlock:(id (^)(YapDatabaseReadTransaction* _Nonnull transaction, YapDatabaseViewTransaction* _Nonnull view))block;

@end

NS_ASSUME_NONNULL_END