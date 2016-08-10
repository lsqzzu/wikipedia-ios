
#import "WMFDatabase.h"
#import <YapDataBase/YapDatabase.h>
#import <YapDataBase/YapDatabaseView.h>

@interface WMFDatabase ()

@property (nonatomic, strong) NSMutableArray<id<WMFDatabaseChangeHandler> >* changeHandlers;

@property (nonatomic, strong, readwrite) YapDatabaseConnection* articleReferenceReadConnection;
@property (nonatomic, strong, readwrite) YapDatabaseConnection* articleContentReadConnection;

@end

@implementation WMFDatabase

- (instancetype)init {
    NSString* databasePath = [[self class] databasePath];
    DDLogVerbose(@"databasePath: %@", databasePath);
    self = [super initWithPath:databasePath];
    if (self) {
        self.changeHandlers = [NSMutableArray array];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(yapDatabaseModified:)
                                                     name:YapDatabaseModifiedNotification
                                                   object:self];
    }
    return self;
}

- (YapDatabaseConnection*)articleReferenceReadConnection {
    if (!_articleReferenceReadConnection) {
        _articleReferenceReadConnection = [self newLongLivedReadConnection];
    }
    return _articleReferenceReadConnection;
}

- (YapDatabaseConnection*)articleContentReadConnection {
    if (!_articleContentReadConnection) {
        _articleContentReadConnection                  = [self newLongLivedReadConnection];
        _articleContentReadConnection.objectCacheLimit = 10;
    }
    return _articleContentReadConnection;
}

- (YapDatabaseConnection*)newReadConnection {
    YapDatabaseConnection* conn = [self newConnection];
    conn.objectCacheLimit   = 100;
    conn.metadataCacheLimit = 0;
    return conn;
}

- (YapDatabaseConnection*)newLongLivedReadConnection {
    YapDatabaseConnection* conn = [self newConnection];
    conn.objectCacheLimit   = 100;
    conn.metadataCacheLimit = 0;
    [conn beginLongLivedReadTransaction];
    return conn;
}

- (YapDatabaseConnection*)newWriteConnection {
    YapDatabaseConnection* conn = [self newConnection];
    conn.objectCacheLimit   = 0;
    conn.metadataCacheLimit = 0;
    return conn;
}

- (void)registerView:(YapDatabaseView*)view withName:(NSString*)name {
    [self registerExtension:view withName:name];
}

- (void)registerChangeHandler:(id<WMFDatabaseChangeHandler>)changeHandler {
    [self.changeHandlers addObject:changeHandler];
}

- (void)unregisterChangeHandler:(id<WMFDatabaseChangeHandler>)changeHandler {
    [self.changeHandlers removeObject:changeHandler];
}

- (void)yapDatabaseModified:(NSNotification*)notification {
    [self processNotificationForConnection:self.articleReferenceReadConnection];
//    [self processNotificationForConnection:self.articleContentReadConnection];
#warning you can not send notifications to listeners for connections that they arent using
    //IOW you can only send processchanges to listenders of a specific connection
}

- (void)processNotificationForConnection:(YapDatabaseConnection*)connection {
    // Jump to the most recent commit.
    // End & Re-Begin the long-lived transaction atomically.
    // Also grab all the notifications for all the commits that I jump.
    // If the UI is a bit backed up, I may jump multiple commits.
    NSArray* notifications = [connection beginLongLivedReadTransaction];
    if ([notifications count] == 0) {
        return;
    }
    [self.changeHandlers enumerateObjectsUsingBlock:^(id < WMFDatabaseChangeHandler > _Nonnull obj, NSUInteger idx, BOOL* _Nonnull stop) {
        [obj processChanges:notifications onConnection:connection];
    }];
}

#pragma mark - Utility

+ (NSString*)databasePath {
    NSString* databaseName = @"WikipediaYap.sqlite";

    NSURL* baseURL = [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory
                                                            inDomain:NSUserDomainMask
                                                   appropriateForURL:nil
                                                              create:YES
                                                               error:NULL];

    NSURL* databaseURL = [baseURL URLByAppendingPathComponent:databaseName isDirectory:NO];

    return databaseURL.filePathURL.path;
}

@end
