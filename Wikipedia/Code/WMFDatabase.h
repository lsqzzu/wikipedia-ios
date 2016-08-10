
#import <Foundation/Foundation.h>
#import <YapDataBase/YapDatabase.h>
#import <YapDataBase/YapDatabaseView.h>
#import <YapDataBase/YapDatabaseFilteredView.h>

@protocol WMFDatabaseChangeHandler <NSObject>

- (void)processChanges:(NSArray<YapDatabaseViewRowChange*>*)changes onConnection:(YapDatabaseConnection*)connection;

@end

@interface WMFDatabase : YapDatabase

/**
 *  Connection to read article references on.
 *  This connection has cache settings optimized for reading article references in the UI.
 *  It is reccomended to use this connection to make sure these cache settings are enforced app wide
 */
@property (nonatomic, strong, readonly) YapDatabaseConnection* articleReferenceReadConnection;

/**
 *  Connection to read article content on.
 *  This connection has cache settings optimized for reading article content in the UI.
 *  It is reccomended to use this connection to make sure these cache settings are enforced app wide
 */
@property (nonatomic, strong, readonly) YapDatabaseConnection* articleContentReadConnection;

/**
 *  The default database path
 *
 *  @return A path
 */
+ (NSString*)databasePath;

/**
 *  Initialize the DB with the default path
 *
 *  @return a database
 */
- (instancetype)init NS_DESIGNATED_INITIALIZER;


- (YapDatabaseConnection*)newReadConnection;

- (YapDatabaseConnection*)newLongLivedReadConnection;

- (YapDatabaseConnection*)newWriteConnection;

#pragma mark - Convienence

/**
 *  Convienence method for registerExtension:withName:
 *
 *  @param view The view to register
 *  @param name The neame of the view
 */
- (void)registerView:(YapDatabaseView*)view withName:(NSString*)name;

#pragma mark - WMFDatabaseChangeHandler

/**
 *  Register a changeHandler to recieve notifications when
 *  a changes are processed on a connection managed by this
 *  object.
 *
 *  The database will strongly reference any registered connections
 *  Be sure not to cause a retain loop strongly retaining the DB
 *
 *  @param changeHandler The changeHandler to notify
 */
- (void)registerChangeHandler:(id<WMFDatabaseChangeHandler>)changeHandler;

/**
 *  De-register a changeHandler so it no longer recieves notifications
 *
 *  @param changeHandler The changeHandler to stop notifying
 */
- (void)unregisterChangeHandler:(id<WMFDatabaseChangeHandler>)changeHandler;



@end
