#import "BelugaRenderedAXNegativeFixtures.h"
#import <AppKit/AppKit.h>

@protocol BRAXNegativeWitness <NSObject>
- (NSUInteger)fixtureTargetCalls;
- (NSUInteger)fixturePermissionCalls;
@end

@interface BRAXNegativeWitnessNode : NSObject <BRAXNegativeWitness> {
@protected
    NSUInteger _targetCalls;
    NSUInteger _permissionCalls;
}
@end
@implementation BRAXNegativeWitnessNode
- (NSUInteger)fixtureTargetCalls { return _targetCalls; }
- (NSUInteger)fixturePermissionCalls { return _permissionCalls; }
@end

@interface BRAXNegativeValidNode : BRAXNegativeWitnessNode
@property(nonatomic, readonly) BelugaRenderedAXFixture kind;
- (instancetype)initWithKind:(BelugaRenderedAXFixture)kind;
@end
@implementation BRAXNegativeValidNode
- (instancetype)initWithKind:(BelugaRenderedAXFixture)kind {
    if ((self = [super init])) _kind = kind;
    return self;
}
- (NSString *)fixtureText {
    if (_kind == BelugaRenderedAXFixtureText4096 || _kind == BelugaRenderedAXFixtureText4097) {
        const NSUInteger count = _kind == BelugaRenderedAXFixtureText4096 ? 4096 : 4097;
        return [@"" stringByPaddingToLength:count withString:@"x" startingAtIndex:0];
    }
    if (_kind == BelugaRenderedAXFixtureEmoji4096 || _kind == BelugaRenderedAXFixtureEmoji4098) {
        const unichar pair[] = { 0xD83D, 0xDE00 };
        NSString *unit = [NSString stringWithCharacters:pair length:2];
        NSMutableString *text = [NSMutableString string];
        const NSUInteger count = _kind == BelugaRenderedAXFixtureEmoji4096 ? 2048 : 2049;
        for (NSUInteger i = 0; i < count; i++) [text appendString:unit];
        return text;
    }
    return @"Move media to phone";
}
- (id)accessibilityRole {
    _targetCalls++;
    if (_kind >= BelugaRenderedAXFixtureText4096 && _kind <= BelugaRenderedAXFixtureEmoji4098) {
        return [self fixtureText];
    }
    return NSAccessibilityButtonRole;
}
- (id)accessibilityIdentifier {
    _targetCalls++;
    return _kind == BelugaRenderedAXFixtureDeniedLabel ? @"beluga.move-media-to-phone" : [self fixtureText];
}
- (id)accessibilityLabel {
    _targetCalls++;
    if (_kind == BelugaRenderedAXFixtureWrongStringValue) return @7;
    if (_kind == BelugaRenderedAXFixtureThrowingLabel) {
        @throw [NSException exceptionWithName:@"BelugaRenderedAXFixtureException" reason:@"fixture" userInfo:nil];
    }
    return [self fixtureText];
}
- (id)accessibilityValue { _targetCalls++; return [self fixtureText]; }
- (id)accessibilityChildren {
    _targetCalls++;
    if (_kind == BelugaRenderedAXFixtureWrongChildrenValue) return @7;
    const NSUInteger count = _kind == BelugaRenderedAXFixtureChildren128 ? 128
        : (_kind == BelugaRenderedAXFixtureChildren129 ? 129 : 0);
    NSMutableArray *children = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) [children addObject:[[NSObject alloc] init]];
    return children;
}
- (BOOL)isAccessibilityEnabled {
    _targetCalls++;
    if (_kind == BelugaRenderedAXFixtureThrowingEnabled) {
        @throw [NSException exceptionWithName:@"BelugaRenderedAXFixtureException" reason:@"fixture" userInfo:nil];
    }
    return NO;
}
- (BOOL)accessibilityPerformPress {
    _targetCalls++;
    if (_kind == BelugaRenderedAXFixtureThrowingPress) {
        @throw [NSException exceptionWithName:@"BelugaRenderedAXFixtureException" reason:@"fixture" userInfo:nil];
    }
    return NO;
}
// Deliberately no title or permission implementation in this title-less base.
@end

@interface BRAXNegativeTitledNode : BRAXNegativeValidNode
@end
@implementation BRAXNegativeTitledNode
- (id)accessibilityTitle {
    _targetCalls++;
    return self.kind == BelugaRenderedAXFixtureNilTitle ? nil : [self fixtureText];
}
@end

@interface BRAXNegativeDeniedNode : BRAXNegativeTitledNode
@end
@implementation BRAXNegativeDeniedNode
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    _permissionCalls++;
    switch (self.kind) {
        case BelugaRenderedAXFixtureDeniedLabel: return selector != @selector(accessibilityLabel);
        case BelugaRenderedAXFixtureDeniedEnabled: return selector != @selector(isAccessibilityEnabled);
        case BelugaRenderedAXFixtureDeniedPress: return selector != @selector(accessibilityPerformPress);
        case BelugaRenderedAXFixtureDeniedTitle: return selector != @selector(accessibilityTitle);
        default: return YES;
    }
}
@end

// Static text requires value, not label. This concrete class intentionally has
// no title method and genuinely denies label; the required value is independent.
@interface BRAXNegativeStaticTextNode : BRAXNegativeValidNode
@end
@implementation BRAXNegativeStaticTextNode
- (id)accessibilityRole {
    _targetCalls++;
    return self.kind == BelugaRenderedAXFixtureStaticTextWrongRole
        ? NSAccessibilityButtonRole : NSAccessibilityStaticTextRole;
}
- (id)accessibilityIdentifier { _targetCalls++; return @"beluga.render-test-sentinel"; }
- (id)accessibilityValue {
    _targetCalls++;
    return self.kind == BelugaRenderedAXFixtureStaticTextWrongValue
        ? @"wrong required value" : @"Rendered menu test host";
}
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    _permissionCalls++;
    if (selector == @selector(accessibilityLabel)) return NO;
    if (self.kind == BelugaRenderedAXFixtureStaticTextDeniedValue &&
        selector == @selector(accessibilityValue)) return NO;
    return YES;
}
@end

// Wrong return types are concrete declarations on a base with NO AX methods.
// A safe bridge must reject their encodings before these bodies are entered.
@interface BRAXNegativeWrongObject : BRAXNegativeWitnessNode
@end
@implementation BRAXNegativeWrongObject
- (NSInteger)accessibilityLabel { _targetCalls++; return 7; }
@end
@interface BRAXNegativeWrongEnabled : BRAXNegativeWitnessNode
@end
@implementation BRAXNegativeWrongEnabled
- (NSInteger)isAccessibilityEnabled { _targetCalls++; return 7; }
@end
@interface BRAXNegativeWrongPress : BRAXNegativeWitnessNode
@end
@implementation BRAXNegativeWrongPress
- (NSInteger)accessibilityPerformPress { _targetCalls++; return 7; }
@end
@interface BRAXNegativeWrongPermissionReturn : BRAXNegativeValidNode
@end
@implementation BRAXNegativeWrongPermissionReturn
- (NSInteger)isAccessibilitySelectorAllowed:(SEL)selector { (void)selector; _permissionCalls++; return 1; }
@end
@interface BRAXNegativeWrongPermissionArgument : BRAXNegativeValidNode
@end
@implementation BRAXNegativeWrongPermissionArgument
- (BOOL)isAccessibilitySelectorAllowed:(id)object { (void)object; _permissionCalls++; return YES; }
@end

NSObject *BelugaRenderedAXMakeFixture(BelugaRenderedAXFixture kind) {
    switch (kind) {
        case BelugaRenderedAXFixtureNoMethods: return [[BRAXNegativeWitnessNode alloc] init];
        case BelugaRenderedAXFixtureWrongObjectSignature: return [[BRAXNegativeWrongObject alloc] init];
        case BelugaRenderedAXFixtureWrongEnabledSignature: return [[BRAXNegativeWrongEnabled alloc] init];
        case BelugaRenderedAXFixtureWrongPressSignature: return [[BRAXNegativeWrongPress alloc] init];
        case BelugaRenderedAXFixtureWrongPermissionReturn: return [[BRAXNegativeWrongPermissionReturn alloc] initWithKind:kind];
        case BelugaRenderedAXFixtureWrongPermissionArgument: return [[BRAXNegativeWrongPermissionArgument alloc] initWithKind:kind];
        case BelugaRenderedAXFixtureStaticTextExactValue:
        case BelugaRenderedAXFixtureStaticTextDeniedValue:
        case BelugaRenderedAXFixtureStaticTextWrongValue:
        case BelugaRenderedAXFixtureStaticTextWrongRole: return [[BRAXNegativeStaticTextNode alloc] initWithKind:kind];
        case BelugaRenderedAXFixtureDeniedLabel:
        case BelugaRenderedAXFixtureDeniedEnabled:
        case BelugaRenderedAXFixtureDeniedPress:
        case BelugaRenderedAXFixtureDeniedTitle: return [[BRAXNegativeDeniedNode alloc] initWithKind:kind];
        case BelugaRenderedAXFixtureNilTitle:
        case BelugaRenderedAXFixtureText4096:
        case BelugaRenderedAXFixtureText4097:
        case BelugaRenderedAXFixtureEmoji4096:
        case BelugaRenderedAXFixtureEmoji4098: return [[BRAXNegativeTitledNode alloc] initWithKind:kind];
        case BelugaRenderedAXFixtureGenuineNo:
        case BelugaRenderedAXFixtureChildren128:
        case BelugaRenderedAXFixtureChildren129:
        case BelugaRenderedAXFixtureWrongChildrenValue:
        case BelugaRenderedAXFixtureThrowingLabel:
        case BelugaRenderedAXFixtureThrowingEnabled:
        case BelugaRenderedAXFixtureThrowingPress:
        case BelugaRenderedAXFixtureWrongStringValue: return [[BRAXNegativeValidNode alloc] initWithKind:kind];
    }
    return nil;
}

NSUInteger BelugaRenderedAXFixtureTargetCalls(NSObject *node) {
    return [node conformsToProtocol:@protocol(BRAXNegativeWitness)]
        ? [(id<BRAXNegativeWitness>)node fixtureTargetCalls] : NSNotFound;
}
NSUInteger BelugaRenderedAXFixturePermissionCalls(NSObject *node) {
    return [node conformsToProtocol:@protocol(BRAXNegativeWitness)]
        ? [(id<BRAXNegativeWitness>)node fixturePermissionCalls] : NSNotFound;
}
