

#import <Foundation/Foundation.h>
#import "WMFDatabase.h"
#import "WMFDataSource.h"

NS_ASSUME_NONNULL_BEGIN

@interface WMFDatabaseDataSource : NSObject <WMFDataSource, WMFDatabaseChangeHandler>

@property (readonly, weak, nonatomic) YapDatabaseConnection* connection;
@property (readonly, strong, nonatomic) YapDatabaseViewMappings* mappings;

- (instancetype)initWithConnection:(YapDatabaseConnection*)connection mappings:(YapDatabaseViewMappings*)mappings NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END