#import "BelugaRenderedAXTestSupport.h"
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

static BOOL BRAXExactCopiedType(char *type, const char *expected) {
    const BOOL equal = type != NULL && strcmp(type, expected) == 0;
    free(type);
    return equal;
}

// Require a concrete instance method and exact return/self/_cmd/argument shape.
// Dynamic forwarding or an unknown signature cannot be credited as a getter.
static BelugaRenderedAXStatus BRAXShape(NSObject *node, SEL selector,
                                       const char *returnType, BOOL selectorArgument) {
    if (node == nil || object_isClass(node) || selector == NULL) {
        return BelugaRenderedAXStatusInvalidArgument;
    }
    if (![node respondsToSelector:selector]) return BelugaRenderedAXStatusMissingSelector;
    Method method = class_getInstanceMethod(object_getClass(node), selector);
    if (method == NULL || method_getNumberOfArguments(method) != (selectorArgument ? 3 : 2)) {
        return BelugaRenderedAXStatusMalformedSignature;
    }
    if (!BRAXExactCopiedType(method_copyReturnType(method), returnType) ||
        !BRAXExactCopiedType(method_copyArgumentType(method, 0), @encode(id)) ||
        !BRAXExactCopiedType(method_copyArgumentType(method, 1), @encode(SEL))) {
        return BelugaRenderedAXStatusMalformedSignature;
    }
    if (selectorArgument &&
        !BRAXExactCopiedType(method_copyArgumentType(method, 2), @encode(SEL))) {
        return BelugaRenderedAXStatusMalformedSignature;
    }
    return BelugaRenderedAXStatusOk;
}

static BelugaRenderedAXStatus BRAXAdmission(NSObject *node, SEL selector,
                                           const char *returnType) {
    BelugaRenderedAXStatus status = BRAXShape(node, selector, returnType, NO);
    if (status != BelugaRenderedAXStatusOk) {
        Method method = node != nil && !object_isClass(node) && selector != NULL
            ? class_getInstanceMethod(object_getClass(node), selector) : NULL;
        const char *encoding = method == NULL ? NULL : method_getTypeEncoding(method);
        if (encoding != NULL && strnlen(encoding, 4097) <= 4096) {
            fprintf(stderr, "RENDERED_MENU_AX_SIGNATURE_REFUSAL selector=%s encoding=%s status=%ld\n",
                    sel_getName(selector), encoding, (long)status);
        }
        return status;
    }
    const SEL permission = @selector(isAccessibilitySelectorAllowed:);
    if ([node respondsToSelector:permission]) {
        status = BRAXShape(node, permission, @encode(BOOL), YES);
        if (status != BelugaRenderedAXStatusOk) return status;
        const BOOL allowed = [(id<NSAccessibility>)node isAccessibilitySelectorAllowed:selector];
        if (allowed != NO && allowed != YES) return BelugaRenderedAXStatusMalformedValue;
        if (allowed == NO) {
            return BelugaRenderedAXStatusDeniedSelector;
        }
    }
    // The optional permission method is respected if present. It is never
    // synthesized, overridden, or recursively authorized by the test bridge.
    return BelugaRenderedAXStatusOk;
}

static SEL BRAXObjectSelector(BelugaRenderedAXProperty property) {
    switch (property) {
        case BelugaRenderedAXPropertyRole: return @selector(accessibilityRole);
        case BelugaRenderedAXPropertyIdentifier: return @selector(accessibilityIdentifier);
        case BelugaRenderedAXPropertyLabel: return @selector(accessibilityLabel);
        case BelugaRenderedAXPropertyTitle: return @selector(accessibilityTitle);
        case BelugaRenderedAXPropertyValue: return @selector(accessibilityValue);
        case BelugaRenderedAXPropertyChildren: return @selector(accessibilityChildren);
    }
    return NULL;
}

BelugaRenderedAXStatus BelugaRenderedAXReadObject(NSObject *node,
        BelugaRenderedAXProperty property, id __autoreleasing *output) {
    if (output == NULL) return BelugaRenderedAXStatusInvalidArgument;
    *output = nil;
    if (![NSThread isMainThread]) return BelugaRenderedAXStatusOffMainThread;
    @try {
        const SEL selector = BRAXObjectSelector(property);
        BelugaRenderedAXStatus status = BRAXAdmission(node, selector, @encode(id));
        if (status != BelugaRenderedAXStatusOk) return status;
        id<NSAccessibility> accessible = (id<NSAccessibility>)node;
        id value = nil;
        switch (property) {
            case BelugaRenderedAXPropertyRole: value = [accessible accessibilityRole]; break;
            case BelugaRenderedAXPropertyIdentifier: value = [accessible accessibilityIdentifier]; break;
            case BelugaRenderedAXPropertyLabel: value = [accessible accessibilityLabel]; break;
            case BelugaRenderedAXPropertyTitle: value = [accessible accessibilityTitle]; break;
            case BelugaRenderedAXPropertyValue: value = [accessible accessibilityValue]; break;
            case BelugaRenderedAXPropertyChildren: value = [accessible accessibilityChildren]; break;
        }
        if (property == BelugaRenderedAXPropertyChildren) {
            if (value != nil && ![value isKindOfClass:[NSArray class]]) {
                return BelugaRenderedAXStatusMalformedValue;
            }
            if ([(NSArray *)value count] > 128) return BelugaRenderedAXStatusExcessChildren;
        } else if (value != nil && ![value isKindOfClass:[NSString class]]) {
            // Value is read only for asserted static text, never coerced from
            // numbers/attributed strings into a textual expected result.
            return BelugaRenderedAXStatusMalformedValue;
        } else if (property == BelugaRenderedAXPropertyRole && value == nil) {
            return BelugaRenderedAXStatusMalformedValue;
        }
        if (property != BelugaRenderedAXPropertyChildren && [(NSString *)value length] > 4096) {
            // NSString.length counts UTF-16 code units. Refuse before returning
            // the value to Swift; never truncate or bridge an oversized string.
            return BelugaRenderedAXStatusExcessText;
        }
        *output = value;
        return BelugaRenderedAXStatusOk;
    } @catch (NSException *exception) {
        (void)exception;
        return BelugaRenderedAXStatusRaisedException;
    }
}

BelugaRenderedAXStatus BelugaRenderedAXReadEnabled(NSObject *node, BOOL *output) {
    if (output == NULL) return BelugaRenderedAXStatusInvalidArgument;
    *output = NO;
    if (![NSThread isMainThread]) return BelugaRenderedAXStatusOffMainThread;
    @try {
        BelugaRenderedAXStatus status = BRAXAdmission(node, @selector(isAccessibilityEnabled), @encode(BOOL));
        if (status != BelugaRenderedAXStatusOk) return status;
        const BOOL value = [(id<NSAccessibility>)node isAccessibilityEnabled];
        if (value != NO && value != YES) return BelugaRenderedAXStatusMalformedValue;
        *output = value;
        return BelugaRenderedAXStatusOk;
    } @catch (NSException *exception) {
        (void)exception;
        return BelugaRenderedAXStatusRaisedException;
    }
}

BelugaRenderedAXStatus BelugaRenderedAXPress(NSObject *node, BOOL *accepted) {
    if (accepted == NULL) return BelugaRenderedAXStatusInvalidArgument;
    *accepted = NO;
    if (![NSThread isMainThread]) return BelugaRenderedAXStatusOffMainThread;
    @try {
        BelugaRenderedAXStatus status = BRAXAdmission(node, @selector(accessibilityPerformPress), @encode(BOOL));
        if (status != BelugaRenderedAXStatusOk) return status;
        const BOOL value = [(id<NSAccessibility>)node accessibilityPerformPress];
        if (value != NO && value != YES) return BelugaRenderedAXStatusMalformedValue;
        *accepted = value;
        return BelugaRenderedAXStatusOk;
    } @catch (NSException *exception) {
        (void)exception;
        return BelugaRenderedAXStatusRaisedException;
    }
}
