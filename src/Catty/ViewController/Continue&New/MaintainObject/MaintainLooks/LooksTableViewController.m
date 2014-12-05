/**
 *  Copyright (C) 2010-2014 The Catrobat Team
 *  (http://developer.catrobat.org/credits)
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License as
 *  published by the Free Software Foundation, either version 3 of the
 *  License, or (at your option) any later version.
 *
 *  An additional term exception under section 7 of the GNU Affero
 *  General Public License, version 3, is available at
 *  (http://developer.catrobat.org/license_additional_term)
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with this program.  If not, see http://www.gnu.org/licenses/.
 */

#import "LooksTableViewController.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "ProgramDefines.h"
#import "UIDefines.h"
#import "TableUtil.h"
#import "CellTagDefines.h"
#import "CatrobatImageCell.h"
#import "DarkBlueGradientImageDetailCell.h"
#import "Look.h"
#import "SpriteObject.h"
#import "SegueDefines.h"
#import "ActionSheetAlertViewTags.h"
#import "ScenePresenterViewController.h"
#import "LookImageViewController.h"
#import "ProgramDefines.h"
#import "UIImageView+CatrobatUIImageViewExtensions.h"
#import "Util.h"
#import "UIColor+CatrobatUIColorExtensions.h"
#import "NSString+CatrobatNSStringExtensions.h"
#import "UIImageView+CatrobatUIImageViewExtensions.h"
#import "NSData+Hashes.h"
#import "AppDelegate.h"
#import "LanguageTranslationDefines.h"
#import "RuntimeImageCache.h"
#import "CatrobatActionSheet.h"
#import "CatrobatAlertView.h"
#import "DataTransferMessage.h"
#import "ProgramLoadingInfo.h"
#import "PlaceHolderView.h"

@interface LooksTableViewController () <CatrobatActionSheetDelegate, UIImagePickerControllerDelegate,
                                        UINavigationControllerDelegate, CatrobatAlertViewDelegate,
                                        UITextFieldDelegate, SWTableViewCellDelegate>
@property (nonatomic) BOOL useDetailCells;
@end

@implementation LooksTableViewController

#pragma mark - data helpers
static NSCharacterSet *blockedCharacterSet = nil;
- (NSCharacterSet*)blockedCharacterSet
{
    if (! blockedCharacterSet) {
        blockedCharacterSet = [[NSCharacterSet characterSetWithCharactersInString:kTextFieldAllowedCharacters]
                               invertedSet];
    }
    return blockedCharacterSet;
}

#pragma mark initialization
- (void)initNavigationBar
{
    UIBarButtonItem *editButtonItem = [TableUtil editButtonItemWithTarget:self action:@selector(editAction:)];
    self.navigationItem.rightBarButtonItem = editButtonItem;
}

#pragma mark viewloaded
- (void)viewDidLoad
{
    [super viewDidLoad];
    NSDictionary *showDetails = [[NSUserDefaults standardUserDefaults] objectForKey:kUserDetailsShowDetailsKey];
    NSNumber *showDetailsProgramsValue = (NSNumber*)[showDetails objectForKey:kUserDetailsShowDetailsLooksKey];
    self.useDetailCells = [showDetailsProgramsValue boolValue];
    self.title = self.navigationItem.title = kLocalizedLooks;
    [self initNavigationBar];
    self.placeHolderView.title = kLocalizedLooks;
    [self showPlaceHolder:(! (BOOL)[self.object.lookList count])];
    [self setupToolBar];
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

#pragma mark - actions
- (void)editAction:(id)sender
{
    NSMutableArray *options = [NSMutableArray array];
    if ([self.object.lookList count]) {
        [options addObject:kLocalizedDeleteLooks];
    }
    if (self.useDetailCells) {
        [options addObject:kLocalizedHideDetails];
    } else {
        [options addObject:kLocalizedShowDetails];
    }
#if kIsRelease // kIsRelease
    CatrobatActionSheet *actionSheet = [Util actionSheetWithTitle:kLocalizedThisFeatureIsComingSoon
                                                         delegate:self
                                           destructiveButtonTitle:nil
                                                otherButtonTitles:options
                                                              tag:kEditLooksActionSheetTag
                                                             view:self.navigationController.view];
    // disable all buttons except hide/show details + cancel button
    // (index of cancel button: ([actionSheet.buttons count] - 1))
    for (IBActionSheetButton *button in actionSheet.buttons) {
        if ((button.index != ([actionSheet.buttons count] - 2)) && (button.index != ([actionSheet.buttons count] - 1))) {
            button.enabled = NO;
            [actionSheet setButtonTextColor:[UIColor grayColor] forButtonAtIndex:button.index];
        }
    }
#else // kIsRelease
    [Util actionSheetWithTitle:kLocalizedEditLooks
                      delegate:self
        destructiveButtonTitle:nil
             otherButtonTitles:options
                           tag:kEditLooksActionSheetTag
                          view:self.navigationController.view];
#endif // kIsRelease
}

- (void)addLookAction:(id)sender
{
    [self showAddLookActionSheet];
}

- (void)playSceneAction:(id)sender
{
    [self.navigationController setToolbarHidden:YES animated:YES];
    ScenePresenterViewController *vc = [[ScenePresenterViewController alloc] initWithProgram:[Program programWithLoadingInfo:[Util lastUsedProgramLoadingInfo]]];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)addLookActionWithName:(NSString*)lookName look:(Look*)look
{
    look.name = [Util uniqueName:lookName existingNames:[self.object allLookNames]];
    // rename temporary file name (example: "temp_D41D8CD98F00B204E9800998ECF8427E.png") as well
    AppDelegate *appDelegate = (AppDelegate*)[UIApplication sharedApplication].delegate;
    NSString *oldPath = [self.object pathForLook:look];
    NSArray *fileNameParts = [look.fileName componentsSeparatedByString:@"."];
    NSString *hash = [[[fileNameParts firstObject] componentsSeparatedByString:kResourceFileNameSeparator] lastObject];
    NSString *fileExtension = [fileNameParts lastObject];
    look.fileName = [NSString stringWithFormat:@"%@%@%@.%@", hash, kResourceFileNameSeparator,
                     look.name, fileExtension];
    NSString *newPath = [self.object pathForLook:look];
    [appDelegate.fileManager moveExistingFileAtPath:oldPath toPath:newPath overwrite:YES];
    [self.dataCache removeObjectForKey:look.fileName]; // just to ensure
    [self.object addLook:look];

    [self showPlaceHolder:NO];
    NSInteger numberOfRowsInLastSection = [self tableView:self.tableView numberOfRowsInSection:0];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(numberOfRowsInLastSection - 1) inSection:0];
    [self.tableView insertRowsAtIndexPaths:@[indexPath]
                          withRowAnimation:UITableViewRowAnimationBottom];
}

- (void)copyLookActionWithSourceLook:(Look*)sourceLook
{
    [self showLoadingView];
    NSString *nameOfCopiedLook = [Util uniqueName:sourceLook.name existingNames:[self.object allLookNames]];
    [self.object copyLook:sourceLook withNameForCopiedLook:nameOfCopiedLook];
    NSInteger numberOfRowsInLastSection = [self tableView:self.tableView numberOfRowsInSection:0];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(numberOfRowsInLastSection - 1) inSection:0];
    [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationBottom];
}

- (void)renameLookActionToName:(NSString*)newLookName look:(Look*)look
{
    if ([newLookName isEqualToString:look.name])
        return;

    [self showLoadingView];
    newLookName = [Util uniqueName:newLookName existingNames:[self.object allLookNames]];
    [self.object renameLook:look toName:newLookName];
    NSUInteger lookIndex = [self.object.lookList indexOfObject:look];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:lookIndex inSection:0];
    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)confirmDeleteSelectedLooksAction:(id)sender
{
    NSArray *selectedRowsIndexPaths = [self.tableView indexPathsForSelectedRows];
    if (! [selectedRowsIndexPaths count]) {
        // nothing selected, nothing to delete...
        [super exitEditingMode];
        return;
    }
    [self deleteSelectedLooksAction];
}

- (void)deleteSelectedLooksAction
{
    [self showLoadingView];
    NSArray *selectedRowsIndexPaths = [self.tableView indexPathsForSelectedRows];
    NSMutableArray *looksToRemove = [NSMutableArray arrayWithCapacity:[selectedRowsIndexPaths count]];
    for (NSIndexPath *selectedRowIndexPath in selectedRowsIndexPaths) {
        Look *look = (Look*)[self.object.lookList objectAtIndex:selectedRowIndexPath.row];
        [looksToRemove addObject:look];
        [self.dataCache removeObjectForKey:look.fileName];
    }
    [self.object removeLooks:looksToRemove];
    [super exitEditingMode];
    [self.tableView deleteRowsAtIndexPaths:selectedRowsIndexPaths withRowAnimation:UITableViewRowAnimationNone];
    [self showPlaceHolder:(! (BOOL)[self.object.lookList count])];
}

- (void)deleteLookForIndexPath:(NSIndexPath*)indexPath
{
    [self showLoadingView];
    Look *look = (Look*)[self.object.lookList objectAtIndex:indexPath.row];
    [self.dataCache removeObjectForKey:look.fileName];
    [self.object removeLook:look];
    [self.tableView deleteRowsAtIndexPaths:@[indexPath]
                          withRowAnimation:UITableViewRowAnimationNone];
    [self showPlaceHolder:(! (BOOL)[self.object.lookList count])];
}

#pragma mark - Table view data source
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.object.lookList count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = kImageCell;
    static NSString *DetailCellIdentifier = kDetailImageCell;
    UITableViewCell *cell = nil;
    if (! self.useDetailCells) {
        cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
    } else {
        cell = [tableView dequeueReusableCellWithIdentifier:DetailCellIdentifier forIndexPath:indexPath];
    }

    if (! [cell conformsToProtocol:@protocol(CatrobatImageCell)] || ! [cell isKindOfClass:[CatrobatBaseCell class]]) {
        return cell;
    }

    CatrobatBaseCell<CatrobatImageCell>* imageCell = (CatrobatBaseCell<CatrobatImageCell>*)cell;
    Look *look = [self.object.lookList objectAtIndex:indexPath.row];
    imageCell.iconImageView.image = nil;
    [imageCell.iconImageView setBorder:[UIColor skyBlueColor] Width:kDefaultImageCellBorderWidth];
    imageCell.rightUtilityButtons = @[[Util slideViewButtonMore], [Util slideViewButtonDelete]];
    imageCell.delegate = self;

    imageCell.iconImageView.contentMode = UIViewContentModeScaleAspectFit;
    RuntimeImageCache *imageCache = [RuntimeImageCache sharedImageCache];
    NSString *previewImagePath = [self.object previewImagePathForLookAtIndex:indexPath.row];
    NSString *imagePath = [self.object pathForLook:look];
    imageCell.iconImageView.image = nil;
    imageCell.indexPath = indexPath;

    UIImage *image = [imageCache cachedImageForPath:previewImagePath];
    if (! image) {
        [imageCache loadThumbnailImageFromDiskWithThumbnailPath:previewImagePath
                                                      imagePath:imagePath
                                                  thumbnailFrameSize:CGSizeMake(kPreviewImageWidth, kPreviewImageHeight)
                                                   onCompletion:^(UIImage *img){
                                                       // check if cell still needed
                                                       if ([imageCell.indexPath isEqual:indexPath]) {
                                                           imageCell.iconImageView.image = img;
                                                           [imageCell setNeedsLayout];
                                                       }
                                                   }];
    } else {
        imageCell.iconImageView.image = image;
    }
    imageCell.titleLabel.text = look.name;

    if (self.useDetailCells && [cell isKindOfClass:[DarkBlueGradientImageDetailCell class]]) {
        DarkBlueGradientImageDetailCell *detailCell = (DarkBlueGradientImageDetailCell*)imageCell;
        detailCell.topLeftDetailLabel.textColor = [UIColor whiteColor];
        detailCell.topLeftDetailLabel.text = [NSString stringWithFormat:@"%@:", kLocalizedMeasure];
        detailCell.topRightDetailLabel.textColor = [UIColor whiteColor];

        NSValue *value = [self.dataCache objectForKey:look.fileName];
        CGSize dimensions;
        if (! value) {
            dimensions = [self.object dimensionsOfLook:look];
            [self.dataCache setObject:[NSValue valueWithCGSize:dimensions] forKey:look.fileName];
        } else {
            dimensions = [value CGSizeValue];
        }
        detailCell.topRightDetailLabel.text = [NSString stringWithFormat:@"%lux%lu",
                                               (unsigned long)dimensions.width,
                                               (unsigned long)dimensions.height];
        detailCell.bottomLeftDetailLabel.textColor = [UIColor whiteColor];
        detailCell.bottomLeftDetailLabel.text = [NSString stringWithFormat:@"%@:", kLocalizedSize];
        detailCell.bottomRightDetailLabel.textColor = [UIColor whiteColor];
        NSUInteger resultSize = [self.object fileSizeOfLook:look];
        NSNumber *sizeOfSound = [NSNumber numberWithUnsignedInteger:resultSize];
        detailCell.bottomRightDetailLabel.text = [NSByteCountFormatter stringFromByteCount:[sizeOfSound unsignedIntegerValue]
                                                                                countStyle:NSByteCountFormatterCountStyleBinary];
        return detailCell;
    }
    return imageCell;
}

- (CGFloat)tableView:(UITableView*)tableView heightForRowAtIndexPath:(NSIndexPath*)indexPath
{
  return [TableUtil heightForImageCell];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
    static NSString *segueToImage = kSegueToImage;
    if (! self.editing) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        if ([self shouldPerformSegueWithIdentifier:segueToImage sender:cell]) {
            [self performSegueWithIdentifier:segueToImage sender:cell];
        }
    }
}

#pragma mark - Navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    static NSString* segueToImageIdentifier = kSegueToImage;
    UIViewController* destController = segue.destinationViewController;

    if ([sender isKindOfClass:[UITableViewCell class]]) {
        UITableViewCell *cell = (UITableViewCell*)sender;
        NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
        if ([segue.identifier isEqualToString:segueToImageIdentifier]) {
            if ([destController isKindOfClass:[LookImageViewController class]]) {
                LookImageViewController *livc = (LookImageViewController*)destController;
                if ([livc respondsToSelector:@selector(setImageName:)] && [livc respondsToSelector:@selector(setImagePath:)]) {
                    Look *look = [self.object.lookList objectAtIndex:indexPath.row];
                    [livc performSelector:@selector(setImageName:) withObject:look.name];
                    NSString *lookImagePath = [self.object pathForLook:look];
                    [livc performSelector:@selector(setImagePath:) withObject:lookImagePath];
                }
            }
        }
    }
}

#pragma mark - swipe delegates
- (void)swipeableTableViewCell:(SWTableViewCell *)cell didTriggerRightUtilityButtonWithIndex:(NSInteger)index
{
    [cell hideUtilityButtonsAnimated:YES];
    if (index == 0) {
        // More button was pressed
        NSArray *options = @[kLocalizedCopy, kLocalizedRename];
#if kIsRelease // kIsRelease
        CatrobatActionSheet *actionSheet = [Util actionSheetWithTitle:kLocalizedThisFeatureIsComingSoon
                                                             delegate:self
                                               destructiveButtonTitle:nil
                                                    otherButtonTitles:options
                                                                  tag:kEditLookActionSheetTag
                                                                 view:self.navigationController.view];
        // disable all buttons except cancel button (index of cancel button: ([actionSheet.buttons count] - 1))
        for (IBActionSheetButton *button in actionSheet.buttons) {
            if (button.index != ([actionSheet.buttons count] - 1)) {
                button.enabled = NO;
                [actionSheet setButtonTextColor:[UIColor grayColor] forButtonAtIndex:button.index];
            }
        }
#else // kIsRelease
        CatrobatActionSheet *actionSheet = [Util actionSheetWithTitle:kLocalizedEditLook
                                                             delegate:self
                                               destructiveButtonTitle:nil
                                                    otherButtonTitles:options
                                                                  tag:kEditLookActionSheetTag
                                                                 view:self.navigationController.view];
#endif // kIsRelease
        NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
        NSDictionary *payload = @{ kDTPayloadLook : [self.object.lookList objectAtIndex:indexPath.row] };
        DataTransferMessage *message = [DataTransferMessage messageForActionType:kDTMActionEditLook
                                                                     withPayload:[payload mutableCopy]];
        actionSheet.dataTransferMessage = message;
    } else if (index == 1) {
        // Delete button was pressed
#if kIsRelease // kIsRelease
        [Util showComingSoonAlertView];
#else // kIsRelease
        NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
        [cell hideUtilityButtonsAnimated:YES];
        [self performActionOnConfirmation:@selector(deleteLookForIndexPath:)
                           canceledAction:nil
                               withObject:indexPath
                                   target:self
                             confirmTitle:kLocalizedDeleteThisLook
                           confirmMessage:kLocalizedThisActionCannotBeUndone];
#endif // kIsRelease
    }
}

- (BOOL)swipeableTableViewCellShouldHideUtilityButtonsOnSwipe:(SWTableViewCell *)cell
{
    return YES;
}

#pragma mark - UIImagePicker Handler
- (void)presentImagePicker:(UIImagePickerControllerSourceType)sourceType
{
    if (! [UIImagePickerController isSourceTypeAvailable:sourceType])
        return;

    NSArray *availableMediaTypes = [UIImagePickerController availableMediaTypesForSourceType:sourceType];
    if (! [availableMediaTypes containsObject:(NSString *)kUTTypeImage])
        return;

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = sourceType;
    picker.mediaTypes = @[(NSString*)kUTTypeImage];
    picker.allowsEditing = NO;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:^{
        [UIApplication sharedApplication].statusBarStyle = UIStatusBarStyleLightContent;
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    // executed on the main queue
    [self dismissViewControllerAnimated:YES completion:nil];
    UIImage *image = info[UIImagePickerControllerEditedImage];
    if (! image) {
        image = info[UIImagePickerControllerOriginalImage];
    }

    if (! image) {
        return;
    }

    // add image to object now
    NSURL *imageURL = [info objectForKey:UIImagePickerControllerReferenceURL];
    [self showLoadingView];

    ALAssetsLibraryAssetForURLResultBlock resultblock = ^(ALAsset *myasset) {
        // still on the main queue here
        ALAssetRepresentation *representation = [myasset defaultRepresentation];
        NSString *imageFileName = [representation filename];
        NSLog(@"fileName: %@",imageFileName);
        NSArray *imageFileNameParts = [imageFileName componentsSeparatedByString:@"."];
        imageFileName = [imageFileNameParts firstObject];
        NSString *imageFileNameExtension = [imageFileNameParts lastObject];
        if ((! [imageFileName length]) || (! [imageFileNameExtension length])) {
            imageFileName = kLocalizedMyImage;
            imageFileNameExtension = kLocalizedMyImageExtension;
        }

        NSData *imageData = UIImagePNGRepresentation(image);
        NSString *lookName = imageFileName;
        // use temporary filename, will be renamed by user afterwards
        NSString *newImageFileName = [NSString stringWithFormat:@"temp_%@.%@",
                                      [[[imageData md5] stringByReplacingOccurrencesOfString:@"-" withString:@""] uppercaseString],
                                      imageFileNameExtension];
        Look *look = [[Look alloc] initWithName:[Util uniqueName:lookName
                                                   existingNames:[self.object allLookNames]]
                                        andPath:newImageFileName];

        // TODO: outsource this to FileManager
        NSString *newImagePath = [NSString stringWithFormat:@"%@%@/%@",
                                  [self.object projectPath], kProgramImagesDirName, newImageFileName];
        NSString *mediaType = info[UIImagePickerControllerMediaType];
        NSLog(@"Writing file to disk");
        if ([mediaType isEqualToString:@"public.image"]) {
            // leaving the main queue here!
            NSBlockOperation* saveOp = [NSBlockOperation blockOperationWithBlock:^{
                // save image to programs directory
                [imageData writeToFile:newImagePath atomically:YES];
            }];
            // completion block is NOT executed on the main queue
            [saveOp setCompletionBlock:^{
                // execute this on the main queue
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [self hideLoadingView];
                    [self showPlaceHolder:([self.object.lookList count] == 0)];

                    // ask user for image name
                    [Util askUserForTextAndPerformAction:@selector(addLookActionWithName:look:)
                                                  target:self
                                              withObject:look
                                             promptTitle:kLocalizedAddImage
                                           promptMessage:[NSString stringWithFormat:@"%@:", kLocalizedImageName]
                                             promptValue:look.name
                                       promptPlaceholder:kLocalizedEnterYourImageNameHere
                                          minInputLength:kMinNumOfLookNameCharacters
                                          maxInputLength:kMaxNumOfLookNameCharacters
                                     blockedCharacterSet:[self blockedCharacterSet]
                                invalidInputAlertMessage:kLocalizedInvalidImageNameDescription];
                }];
            }];
            NSOperationQueue *queue = [[NSOperationQueue alloc] init];
            [queue addOperation:saveOp];
        }
    };
    ALAssetsLibrary* assetslibrary = [[ALAssetsLibrary alloc] init];
    [assetslibrary assetForURL:imageURL
                   resultBlock:resultblock
                  failureBlock:nil];
}

#pragma mark - text field delegates
- (BOOL)textField:(UITextField*)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString*)characters
{
    if ([characters length] > kMaxNumOfLookNameCharacters) {
        return false;
    }
    return ([characters rangeOfCharacterFromSet:self.blockedCharacterSet].location == NSNotFound);
}

#pragma mark - action sheet delegates
- (void)actionSheet:(CatrobatActionSheet*)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (actionSheet.tag == kEditLooksActionSheetTag) {
        BOOL showHideSelected = NO;
        if ([self.object.lookList count]) {
            if (buttonIndex == 0) {
                // Delete Looks button
                [self setupEditingToolBar];
                [super changeToEditingMode:actionSheet];
            } else if (buttonIndex == 1) {
                showHideSelected = YES;
            }
        } else if (buttonIndex == 0) {
            showHideSelected = YES;
        }
        if (showHideSelected) {
            // Show/Hide Details button
            self.useDetailCells = (! self.useDetailCells);
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            NSDictionary *showDetails = [defaults objectForKey:kUserDetailsShowDetailsKey];
            NSMutableDictionary *showDetailsMutable = nil;
            if (! showDetails) {
                showDetailsMutable = [NSMutableDictionary dictionary];
            } else {
                showDetailsMutable = [showDetails mutableCopy];
            }
            [showDetailsMutable setObject:[NSNumber numberWithBool:self.useDetailCells]
                                   forKey:kUserDetailsShowDetailsLooksKey];
            [defaults setObject:showDetailsMutable forKey:kUserDetailsShowDetailsKey];
            [defaults synchronize];
            [self.tableView reloadData];
        }
    } else if (actionSheet.tag == kEditLookActionSheetTag) {
        if (buttonIndex == 0) {
            // Copy look button
            NSDictionary *payload = (NSDictionary*)actionSheet.dataTransferMessage.payload;
            [self copyLookActionWithSourceLook:(Look*)payload[kDTPayloadLook]];
        } else if (buttonIndex == 1) {
            // Rename look button
            NSDictionary *payload = (NSDictionary*)actionSheet.dataTransferMessage.payload;
            Look *look = (Look*)payload[kDTPayloadLook];
            [Util askUserForTextAndPerformAction:@selector(renameLookActionToName:look:)
                                          target:self
                                      withObject:look
                                     promptTitle:kLocalizedRenameImage
                                   promptMessage:[NSString stringWithFormat:@"%@:", kLocalizedImageName]
                                     promptValue:look.name
                               promptPlaceholder:kLocalizedEnterYourImageNameHere
                                  minInputLength:kMinNumOfLookNameCharacters
                                  maxInputLength:kMaxNumOfLookNameCharacters
                             blockedCharacterSet:[self blockedCharacterSet]
                        invalidInputAlertMessage:kLocalizedInvalidImageNameDescription];
        }
    } else if (actionSheet.tag == kAddLookActionSheetTag) {
        NSInteger importFromCameraIndex = NSIntegerMin;
        NSInteger chooseImageIndex = NSIntegerMin;
        if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
            NSArray *availableMediaTypes = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypeCamera];
            if ([availableMediaTypes containsObject:(NSString *)kUTTypeImage]) {
                importFromCameraIndex = 0;
            }
        }
        if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeSavedPhotosAlbum]) {
            NSArray *availableMediaTypes = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypeSavedPhotosAlbum];
            if ([availableMediaTypes containsObject:(NSString *)kUTTypeImage]) {
                chooseImageIndex = ((importFromCameraIndex == 0) ? 1 : 0);
            }
        }

        if (buttonIndex == importFromCameraIndex) {
            // take picture from camera
            [self presentImagePicker:UIImagePickerControllerSourceTypeCamera];
        } else if (buttonIndex == chooseImageIndex) {
            // choose picture from camera roll
            [self presentImagePicker:UIImagePickerControllerSourceTypeSavedPhotosAlbum];
//        } else if (buttonIndex != actionSheet.cancelButtonIndex) {
//            // implement this after Pocket Paint is fully integrated
//            // draw new image
//            NSLog(@"Draw new image");
//            [Util showComingSoonAlertView];
        }
    }
}

#pragma mark - action sheet
- (void)showAddLookActionSheet
{
    NSMutableArray *buttonTitles = [NSMutableArray array];
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        NSArray *availableMediaTypes = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypeCamera];
        if ([availableMediaTypes containsObject:(NSString *)kUTTypeImage]) {
            [buttonTitles addObject:kLocalizedFromCamera];
        }
    }
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeSavedPhotosAlbum]) {
        NSArray *availableMediaTypes = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypeSavedPhotosAlbum];
        if ([availableMediaTypes containsObject:(NSString *)kUTTypeImage]) {
            [buttonTitles addObject:kLocalizedChooseImage];
        }
    }
//    [buttonTitles addObject:kLocalizedDrawNewImage];

    [Util actionSheetWithTitle:kLocalizedAddLook
                      delegate:self
        destructiveButtonTitle:nil
             otherButtonTitles:buttonTitles
                           tag:kAddLookActionSheetTag
                          view:self.navigationController.view];
}

#pragma mark - helpers
- (void)setupToolBar
{
    [super setupToolBar];
    UIBarButtonItem *flexItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                              target:nil
                                                                              action:nil];
    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                         target:self
                                                                         action:@selector(addLookAction:)];
#if kIsRelease // kIsRelease
    add.enabled = NO;
#endif // kIsRelease
    UIBarButtonItem *play = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPlay
                                                                          target:self
                                                                          action:@selector(playSceneAction:)];
    // XXX: workaround for tap area problem:
    // http://stackoverflow.com/questions/5113258/uitoolbar-unexpectedly-registers-taps-on-uibarbuttonitem-instances-even-when-tap
    UIImageView *imageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"transparent1x1"]];
    UIBarButtonItem *invisibleButton = [[UIBarButtonItem alloc] initWithCustomView:imageView];
    self.toolbarItems = [NSArray arrayWithObjects:flexItem, invisibleButton, add, invisibleButton, flexItem,
                         flexItem, flexItem, invisibleButton, play, invisibleButton, flexItem, nil];
}

- (void)setupEditingToolBar
{
    [super setupEditingToolBar];
    UIBarButtonItem *flexItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                              target:nil
                                                                              action:nil];
    UIBarButtonItem *deleteButton = [[UIBarButtonItem alloc] initWithTitle:kLocalizedDelete
                                                                     style:UIBarButtonItemStylePlain
                                                                    target:self
                                                                    action:@selector(confirmDeleteSelectedLooksAction:)];
    // XXX: workaround for tap area problem:
    // http://stackoverflow.com/questions/5113258/uitoolbar-unexpectedly-registers-taps-on-uibarbuttonitem-instances-even-when-tap
    UIImageView *imageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"transparent1x1"]];
    UIBarButtonItem *invisibleButton = [[UIBarButtonItem alloc] initWithCustomView:imageView];
    self.toolbarItems = [NSArray arrayWithObjects:self.selectAllRowsButtonItem, invisibleButton, flexItem,
                         invisibleButton, deleteButton, nil];
}

@end