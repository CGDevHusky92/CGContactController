//
//  ContactController.m
//  ThisOrThat
//
//  Created by Chase Gorectke on 10/29/13.
//  Copyright Revision Works 2013
//  Engineering A Better World
//

#import <Parse/Parse.h>
#import <AddressBook/AddressBook.h>
#import <CGDataController/CGDataController.h>
#import "CGContactController.h"
#import "FriendsViewController.h"
#import "Friend.h"

#ifdef TAT_LOGGING
#import "CGLogger.h"
#endif

#define kContactsUpdatedNotification @"kContactsUpdatedNotification"

//NSString *const kContactsUpdatedNotification = @"kContactsUpdatedNotification";

@interface CGContactController()

@property (nonatomic, strong) NSMutableArray *contactArray;
@property (atomic) NSLock *addArrayLock;
@property (atomic) NSLock *inviteArrayLock;

@end

@implementation CGContactController
@synthesize addArray=_addArray;
@synthesize inviteArray=_inviteArray;

+ (CGContactController *)sharedContacts
{
    static CGContactController *sharedContacts = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedContacts = [[CGContactController alloc] init];
    });
    return sharedContacts;
}

- (id)init
{
    self = [super init];
    if (self) {
        _inviteArrayLock = [[NSLock alloc] init];
        _addArrayLock = [[NSLock alloc] init];
        _contactArray = [[NSMutableArray alloc] init];
        _addArray = [[NSMutableArray alloc] init];
        _inviteArray = [[NSMutableArray alloc] init];
        [self refreshContacts];
    }
    return self;
}

- (void)refreshContacts
{
    CFErrorRef error = NULL;
    ABAddressBookRef addressBook = ABAddressBookCreateWithOptions(NULL, &error);
    [_addArray removeAllObjects];
    [_inviteArray removeAllObjects];
    if (!error) {
        ABAddressBookRequestAccessWithCompletion(addressBook, ^(bool granted, CFErrorRef error){
            if (granted) {
                if (addressBook != nil) {
                    NSArray *allContacts = (__bridge_transfer NSArray *)ABAddressBookCopyArrayOfAllPeople(addressBook);
                    NSUInteger i = 0;
                    for (i = 0; i < [allContacts count]; i++) {
                        NSMutableArray *personArray = [[NSMutableArray alloc] init];
                        NSMutableArray *nameArray = [[NSMutableArray alloc] init];
                        NSMutableArray *phoneArray = [[NSMutableArray alloc] init];
                        NSMutableArray *emailArray = [[NSMutableArray alloc] init];
                        
                        ABRecordRef contactPerson = (__bridge ABRecordRef)allContacts[i];
                        NSString *firstName = (__bridge_transfer NSString *)ABRecordCopyValue(contactPerson, kABPersonFirstNameProperty);
                        NSString *lastName =  (__bridge_transfer NSString *)ABRecordCopyValue(contactPerson, kABPersonLastNameProperty);
                        NSString *fullName = [NSString stringWithFormat:@"%@ %@", firstName, lastName];
                        
                        if (firstName != nil) {
                            [nameArray addObject:firstName];
                        }
                        if (lastName != nil) {
                            [nameArray addObject:lastName];
                        }
                        if (firstName != nil && lastName != nil) {
                            [nameArray addObject:fullName];
                        }
                        
                        NSUInteger j = 0;
                        // Phone
                        ABMultiValueRef phones = ABRecordCopyValue(contactPerson, kABPersonPhoneProperty);
                        for (j = 0; j < ABMultiValueGetCount(phones); j++) {
                            NSString *phone = (__bridge_transfer NSString *)ABMultiValueCopyValueAtIndex(phones, j);
                            [phoneArray addObject:phone];
                        }
                        
                        // Email
                        ABMultiValueRef emails = ABRecordCopyValue(contactPerson, kABPersonEmailProperty);
                        for (j = 0; j < ABMultiValueGetCount(emails); j++) {
                            NSString *email = (__bridge_transfer NSString *)ABMultiValueCopyValueAtIndex(emails, j);
                            [emailArray addObject:email];
                        }
                        
                        [personArray addObject:nameArray];
                        [personArray addObject:phoneArray];
                        [personArray addObject:emailArray];
                        
                        NSString *personName;
                        if ([[personArray objectAtIndex:0] count] == 3) {
                            personName = [[personArray objectAtIndex:0] objectAtIndex:2];
                        } else if ([[personArray objectAtIndex:0] count] > 0) {
                            personName = [[personArray objectAtIndex:0] objectAtIndex:0];
                        }
                        
                        if (personName != nil) {
                            BOOL exists = false;
                            for (int x = 0; x < [_contactArray count]; x++) {
                                NSString *contactName;
                                if ([[[_contactArray objectAtIndex:x] objectAtIndex:0] count] == 3) {
                                    contactName = [[[_contactArray objectAtIndex:x] objectAtIndex:0] objectAtIndex:2];
                                } else if ([[[_contactArray objectAtIndex:x] objectAtIndex:0] count] > 0) {
                                    contactName = [[[_contactArray objectAtIndex:x] objectAtIndex:0] objectAtIndex:0];
                                }
                                
                                if (contactName != nil) {
                                    if ([contactName isEqualToString:personName]) {
                                        exists = true;
                                        [[[_contactArray objectAtIndex:x] objectAtIndex:0] addObjectsFromArray:[personArray objectAtIndex:0]];
                                        [[[_contactArray objectAtIndex:x] objectAtIndex:1] addObjectsFromArray:[personArray objectAtIndex:1]];
                                        [[[_contactArray objectAtIndex:x] objectAtIndex:2] addObjectsFromArray:[personArray objectAtIndex:2]];
                                    }
                                }
                            }
                            
                            if (!exists) {
                                [_contactArray addObject:personArray];
                            }
                        }
                        
                        CFRelease(phones);
                        CFRelease(emails);
                    }
                }
                
                CFRelease(addressBook);
                [self queryServerForUsers];
            } else {
                NSLog(@"Error: %@", error);
            }
        });
    } else {
        NSLog(@"Error: %@", error);
    }
}

- (void)queryServerForUsers
{
    // Query Parse User by User looking for contact matches multiple or query per user...
    NSMutableArray *orQueries = [[NSMutableArray alloc] init];
    __block NSMutableArray *phoneArray = [[NSMutableArray alloc] init];
    __block NSMutableArray *nameArray = [[NSMutableArray alloc] init];
    for (int i = 0; i < [_contactArray count]; i++) {
        NSString *name = @"";
        NSString *phone = @"";
        if ([[[_contactArray objectAtIndex:i] objectAtIndex:0] count] == 3) {
            name = [[[_contactArray objectAtIndex:i] objectAtIndex:0] objectAtIndex:2];
        } else if ([[[_contactArray objectAtIndex:i] objectAtIndex:0] count] > 0) {
            name = [[[_contactArray objectAtIndex:i] objectAtIndex:0] objectAtIndex:0];
        }
        
        for (int j = 0; j < [[[_contactArray objectAtIndex:i] objectAtIndex:1] count]; j++) {
            phone = [[[_contactArray objectAtIndex:i] objectAtIndex:1] objectAtIndex:j];
            phone = [self phoneCheck:phone];
            if ([phone length] == 10) {
                phone = [NSString stringWithFormat:@"%@%@%@", [phone substringWithRange:NSMakeRange(0, 3)], [phone substringWithRange:NSMakeRange(3, 3)], [phone substringWithRange:NSMakeRange(6, 4)]];
            }
            
            if (![phone isEqualToString:@""] && ![name isEqualToString:@""]) {
                [nameArray addObject:[NSNumber numberWithInt:i]];
                [phoneArray addObject:phone];
                
                PFQuery *userQuery = [PFUser query];
                [userQuery whereKey:@"phone" equalTo:phone];
                [orQueries addObject:userQuery];
            }
        }
    }
    
    if ([orQueries count] > 0) {
        PFQuery *allQueries = [PFQuery orQueryWithSubqueries:orQueries];
        [allQueries findObjectsInBackgroundWithBlock:^(NSArray *objects, NSError *error){
            if (!error) {
                for (int i = 0; i < [objects count]; i++) {
                    if (![[[objects objectAtIndex:i] objectForKey:@"username"] isEqualToString:[[PFUser currentUser] username]]) {
                        // Search to see if friendship already exists
                        BOOL exists = true;
                        NSMutableArray *tempFriends = [[[CGDataController sharedData] managedObjectsForClass:@"Friend" sortedByKey:@"nonuser"] mutableCopy];
                        NSString *friendName = [[objects objectAtIndex:i] objectForKey:@"username"];
                        for (int x = 0; x < [tempFriends count]; x++) {
                            NSString *knownName = [(Friend *)[tempFriends objectAtIndex:x] nonuser];
                            if ([friendName isEqualToString:knownName]) {
                                exists = false;
                            }
                        }
                        if (exists) {
                            [_addArrayLock lock];
                            [_addArray addObject:[objects objectAtIndex:i]];
                            [_addArrayLock unlock];
                        }
                    }
                }
                
                for (int i = 0; i < [_addArray count]; i++) {
                    NSString *addedUserPhone = [[_addArray objectAtIndex:i] objectForKey:@"phone"];
                    for (int x = 0; x < [_contactArray count]; x++) {
                        for (int j = 0; j < [[[_contactArray objectAtIndex:x] objectAtIndex:1] count]; j++) {
                            NSString *phone = [[[_contactArray objectAtIndex:x] objectAtIndex:1] objectAtIndex:j];
                            phone = [self phoneCheck:phone];
                            if ([phone length] == 10) {
                                phone = [NSString stringWithFormat:@"%@%@%@", [phone substringWithRange:NSMakeRange(0, 3)], [phone substringWithRange:NSMakeRange(3, 3)], [phone substringWithRange:NSMakeRange(6, 4)]];
                            }
                            if ([phone isEqualToString:addedUserPhone]) {
                                [_contactArray removeObjectAtIndex:x]; j = 0;
                            }
                        }
                    }
                }
                
                for (int i = 0; i < [_contactArray count]; i++) {
                    [_inviteArrayLock lock];
                    if (![_inviteArray containsObject:[_contactArray objectAtIndex:i]]) {
                        [_inviteArray addObject:[_contactArray objectAtIndex:i]];
                    }
                    [_inviteArrayLock unlock];
                }
                
                [self updateFriendSearchArray];
            } else {
                NSLog(@"Error: %@", [error localizedDescription]);
            }
        }];
    }
}

- (NSString *)phoneCheck:(NSString *)numba
{
    NSCharacterSet *trim = [NSCharacterSet characterSetWithCharactersInString:@"#() +-.*˙˙̇.∙・⁃▪︎ "];
    NSString *newNumba = [[numba componentsSeparatedByCharactersInSet:trim] componentsJoinedByString: @""];
    
    if ([newNumba length] > 10) {
        newNumba = [newNumba substringFromIndex:([newNumba length] - 10)];
    } else if ([newNumba length] < 10) {
        newNumba = @"";
    }
    
    return newNumba;
}

- (void)queryServerForUsersOLD
{
    // Query Parse User by User looking for contact matches multiple or query per user...
    for (int i = 0; i < [_contactArray count]; i++) {
        NSString *name;
        NSString *phone = @"";
        if ([[[_contactArray objectAtIndex:i] objectAtIndex:0] count] == 3) {
            name = [[[_contactArray objectAtIndex:i] objectAtIndex:0] objectAtIndex:2];
        } else if ([[[_contactArray objectAtIndex:i] objectAtIndex:0] count] > 0) {
            name = [[[_contactArray objectAtIndex:i] objectAtIndex:0] objectAtIndex:0];
        }
        
        if ([[[_contactArray objectAtIndex:i] objectAtIndex:1] count] > 0) {
            phone = [[[_contactArray objectAtIndex:i] objectAtIndex:1] objectAtIndex:0];
            if ([phone length] == 11) {
                phone = [phone substringFromIndex:1];
            } else if ([phone length] == 12) {
                if ([[NSString stringWithFormat:@"%c", [phone characterAtIndex:0]] isEqualToString:@"+"]) {
                    phone = [phone substringFromIndex:2];
                } else {
                    phone = [NSString stringWithFormat:@"%@%@%@", [phone substringWithRange:NSMakeRange(0, 3)], [phone substringWithRange:NSMakeRange(4, 3)], [phone substringWithRange:NSMakeRange(8, 4)]];
                }
            } else if ([phone length] > 12) {
                NSString *phoneOne;
                NSString *phoneTwo;
                NSString *phoneThr;
                NSString *temp;
                BOOL phased = false;
                
                for (int x = 0; x < [phone length]; x++) {
                    temp = [NSString stringWithFormat:@"%c", [phone characterAtIndex:x]];
                    if ([temp isEqualToString:@"("]) {
                        phased = true;
                        phoneOne = [phone substringWithRange:NSMakeRange(x + 1, 3)];
                    } else if ([temp isEqualToString:@")"]) {
                        phoneTwo = [phone substringWithRange:NSMakeRange(x + 2, 3)];
                        phoneThr = [phone substringWithRange:NSMakeRange(x + 6, 4)];
                        break;
                    } else if (!phased && [temp isEqualToString:@"-"]) {
                        phoneOne = [phone substringWithRange:NSMakeRange(x + 1, 3)];
                        phoneTwo = [phone substringWithRange:NSMakeRange(x + 5, 3)];
                        phoneThr = [phone substringWithRange:NSMakeRange(x + 9, 4)];
                        break;
                    }
                }
                
                phone = [NSString stringWithFormat:@"%@%@%@", phoneOne, phoneTwo, phoneThr];
            }
        }
        
        if (![phone isEqualToString:@""]) {
            __block int index = i;
            PFQuery *userQuery = [PFUser query];
            [userQuery whereKey:@"phone" equalTo:phone];
            [userQuery getFirstObjectInBackgroundWithBlock:^(PFObject *object, NSError *error){
                if (object != nil) {
                    if (![[object objectForKey:@"username"] isEqualToString:[[PFUser currentUser] username]]) {
                        // Search to see if friendship already exists
                        BOOL exists = true;
                        NSMutableArray *tempFriends = [[[CGDataController sharedData] managedObjectsForClass:@"Friend" sortedByKey:@"nonuser"] mutableCopy];
                        NSString *friendName = [object objectForKey:@"username"];
                        for (int x = 0; x < [tempFriends count]; x++) {
                            NSString *knownName = [(Friend *)[tempFriends objectAtIndex:x] nonuser];
                            if ([friendName isEqualToString:knownName]) {
                                exists = false;
                            }
                        }
                        if (exists) {
                            [_addArrayLock lock];
                            [_addArray addObject:object];
                            [_addArrayLock unlock];
                        }
                    }
                    [self updateFriendSearchArray];
                } else if (object == nil) {
                    [_inviteArrayLock lock];
                    [_inviteArray addObject:[_contactArray objectAtIndex:index]];
                    [_inviteArrayLock unlock];
                    [self updateFriendSearchArray];
                }
            }];
        }
    }
}

- (void)updateFriendSearchArray
{
#warning custom case insensitive comparator
    [_addArray sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"username" ascending:YES]]];
//    _inviteArray = [[_inviteArray sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)] mutableCopy];
    [[NSNotificationCenter defaultCenter] postNotificationName:kContactsUpdatedNotification object:nil];
}

@end
