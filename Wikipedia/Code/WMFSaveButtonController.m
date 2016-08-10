#import "WMFSaveButtonController.h"
#import "MWKSavedPageList.h"
#import "MWKArticle.h"
#import "MWKUserDataStore.h"
#import "SavedPagesFunnel.h"
#import "PiwikTracker+WMFExtensions.h"

@interface WMFSaveButtonController ()

@property (nonatomic, strong) SavedPagesFunnel* savedPagesFunnel;

@end


@implementation WMFSaveButtonController

- (instancetype)initWithControl:(UIControl*)button
                  savedPageList:(MWKSavedPageList*)savedPageList
                            url:(NSURL*)url {
    NSParameterAssert(savedPageList);
    self = [super init];
    if (self) {
        self.control       = button;
        self.url           = url;
        self.savedPageList = savedPageList;
        [self observeSavedPages];
        [self updateSavedButtonState];
    }
    return self;
}

- (instancetype)initWithBarButtonItem:(UIBarButtonItem*)barButtonItem
                        savedPageList:(MWKSavedPageList*)savedPageList
                                  url:(NSURL*)url {
    NSParameterAssert(savedPageList);
    self = [super init];
    if (self) {
        self.barButtonItem = barButtonItem;
        self.url           = url;
        self.savedPageList = savedPageList;
        [self observeSavedPages];
        [self updateSavedButtonState];
    }
    return self;
}

- (void)dealloc {
    [self unobserveSavedPages];
}

#pragma mark - Accessors

- (void)setSavedPageList:(MWKSavedPageList*)savedPageList {
    if (self.savedPageList == savedPageList) {
        return;
    }
    _savedPageList = savedPageList;
    [self updateSavedButtonState];
}

- (void)setUrl:(NSURL*)url {
    if (WMF_EQUAL(self.url, isEqual:, url)) {
        return;
    }
    _url = url;
    [self updateSavedButtonState];
}

- (void)setControl:(UIButton*)button {
    [_control removeTarget:self
                    action:@selector(toggleSave:)
          forControlEvents:UIControlEventTouchUpInside];

    [button addTarget:self
               action:@selector(toggleSave:)
     forControlEvents:UIControlEventTouchUpInside];

    _control = button;
    [self updateSavedButtonState];
}

- (void)setBarButtonItem:(UIBarButtonItem*)barButtonItem {
    [_barButtonItem setTarget:nil];
    [_barButtonItem setAction:nil];
    _barButtonItem = barButtonItem;
    [_barButtonItem setTarget:self];
    [_barButtonItem setAction:@selector(toggleSave:)];
    [self updateSavedButtonState];
}

- (SavedPagesFunnel*)savedPagesFunnel {
    if (!_savedPagesFunnel) {
        _savedPagesFunnel = [[SavedPagesFunnel alloc] init];
    }
    return _savedPagesFunnel;
}

#pragma mark - Notifications

- (void)observeSavedPages {
    [self unobserveSavedPages];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateSavedButtonState) name:MWKSavedPageListDidSaveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateSavedButtonState) name:MWKSavedPageListDidUnsaveNotification object:nil];
}

- (void)unobserveSavedPages {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Save State

- (void)updateSavedButtonState {
    if(self.barButtonItem == nil && self.control == nil){
        return;
    }
    if(self.savedPageList == nil){
        return;
    }
    if(self.url == nil){
        return;
    }
    BOOL isSaved = [self isSaved];
    self.control.selected = isSaved;
    if (isSaved) {
        self.barButtonItem.image = [UIImage imageNamed:@"save-filled"];
    } else {
        self.barButtonItem.image = [UIImage imageNamed:@"save"];
    }
}

- (BOOL)isSaved {
    return [self.savedPageList isSaved:self.url];
}

- (void)toggleSave:(id)sender {
//    [self unobserveSavedPages];
    [self.savedPageList toggleSavedPageForURL:self.url];

    BOOL isSaved = [self.savedPageList isSaved:self.url];
    if (isSaved) {
        [self.savedPagesFunnel logSaveNew];
        [[PiwikTracker wmf_configuredInstance] wmf_logActionSaveInContext:self.analyticsContext contentType:self.analyticsContentType];
    } else {
        [self.savedPagesFunnel logDelete];
        [[PiwikTracker wmf_configuredInstance] wmf_logActionUnsaveInContext:self.analyticsContext contentType:self.analyticsContentType];
    }

//    [self observeSavedPages];
}

@end
