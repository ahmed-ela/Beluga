#import <AppKit/AppKit.h>
#import "BelugaRenderedAXNegativeFixtures.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BelugaRenderedAXStatus) {
    BelugaRenderedAXStatusOk = 0,
    BelugaRenderedAXStatusInvalidArgument,
    BelugaRenderedAXStatusOffMainThread,
    BelugaRenderedAXStatusMissingSelector,
    BelugaRenderedAXStatusMalformedSignature,
    BelugaRenderedAXStatusDeniedSelector,
    BelugaRenderedAXStatusMalformedValue,
    BelugaRenderedAXStatusExcessText,
    BelugaRenderedAXStatusExcessChildren,
    BelugaRenderedAXStatusRaisedException
};

typedef NS_ENUM(NSInteger, BelugaRenderedAXProperty) {
    BelugaRenderedAXPropertyRole = 1,
    BelugaRenderedAXPropertyIdentifier,
    BelugaRenderedAXPropertyLabel,
    BelugaRenderedAXPropertyTitle,
    BelugaRenderedAXPropertyValue,
    BelugaRenderedAXPropertyChildren
};

// An output is meaningful ONLY for StatusOk. Missing/denied/malformed is NOT nil
// text, false enabled, or refused press. The Swift adapter enforces that boundary.
FOUNDATION_EXPORT BelugaRenderedAXStatus BelugaRenderedAXReadObject(
    NSObject *node, BelugaRenderedAXProperty property,
    id _Nullable __autoreleasing * _Nullable output);
FOUNDATION_EXPORT BelugaRenderedAXStatus BelugaRenderedAXReadEnabled(
    NSObject *node, BOOL * _Nullable output);
FOUNDATION_EXPORT BelugaRenderedAXStatus BelugaRenderedAXPress(
    NSObject *node, BOOL * _Nullable accepted);

NS_ASSUME_NONNULL_END
