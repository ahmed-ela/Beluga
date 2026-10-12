#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, BelugaRenderedAXFixture) {
    BelugaRenderedAXFixtureNoMethods = 1,
    BelugaRenderedAXFixtureGenuineNo,
    BelugaRenderedAXFixtureWrongObjectSignature,
    BelugaRenderedAXFixtureWrongEnabledSignature,
    BelugaRenderedAXFixtureWrongPressSignature,
    BelugaRenderedAXFixtureDeniedLabel,
    BelugaRenderedAXFixtureDeniedEnabled,
    BelugaRenderedAXFixtureDeniedPress,
    BelugaRenderedAXFixtureDeniedTitle,
    BelugaRenderedAXFixtureWrongPermissionReturn,
    BelugaRenderedAXFixtureWrongPermissionArgument,
    BelugaRenderedAXFixtureNilTitle,
    BelugaRenderedAXFixtureText4096,
    BelugaRenderedAXFixtureText4097,
    BelugaRenderedAXFixtureEmoji4096,
    BelugaRenderedAXFixtureEmoji4098,
    BelugaRenderedAXFixtureChildren128,
    BelugaRenderedAXFixtureChildren129,
    BelugaRenderedAXFixtureWrongChildrenValue,
    BelugaRenderedAXFixtureThrowingLabel,
    BelugaRenderedAXFixtureThrowingEnabled,
    BelugaRenderedAXFixtureThrowingPress,
    BelugaRenderedAXFixtureWrongStringValue,
    BelugaRenderedAXFixtureStaticTextExactValue,
    BelugaRenderedAXFixtureStaticTextDeniedValue,
    BelugaRenderedAXFixtureStaticTextWrongValue,
    BelugaRenderedAXFixtureStaticTextWrongRole
};
FOUNDATION_EXPORT NSObject * _Nullable BelugaRenderedAXMakeFixture(BelugaRenderedAXFixture kind);
FOUNDATION_EXPORT NSUInteger BelugaRenderedAXFixtureTargetCalls(NSObject *node);
FOUNDATION_EXPORT NSUInteger BelugaRenderedAXFixturePermissionCalls(NSObject *node);
NS_ASSUME_NONNULL_END
