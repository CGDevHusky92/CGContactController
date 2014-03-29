//
//  ContactController.h
//  ThisOrThat
//
//  Created by Chase Gorectke on 10/29/13.
//  Copyright Revision Works 2013
//  Engineering A Better World
//

#import <Foundation/Foundation.h>
#import <AddressBook/AddressBook.h>

@interface CGContactController : NSObject

@property (nonatomic, strong) NSMutableArray *addArray;
@property (nonatomic, strong) NSMutableArray *inviteArray;

+ (CGContactController *)sharedContacts;

@end
