// Copyright (c) 2021 Microsoft, Inc.
// Use of this source code is governed by the MIT license that can be
// found in the LICENSE file.

#include "shell/browser/ui/cocoa/window_buttons_proxy.h"

#include "base/notreached.h"
#include "shell/browser/native_window_mac.h"
#include "shell/browser/ui/cocoa/electron_ns_window.h"

@implementation ButtonsAreaHoverView : NSView

- (id)initWithProxy:(WindowButtonsProxy*)proxy {
  if ((self = [super init])) {
    proxy_ = proxy;
  }
  return self;
}

// Ignore all mouse events.
- (NSView*)hitTest:(NSPoint)aPoint {
  return nil;
}

- (void)updateTrackingAreas {
  [proxy_ updateTrackingAreas];
}

@end

@implementation WindowButtonsProxy

- (id)initWithWindow:(electron::NativeWindowMac*)window {
  is_rtl_ = [titlebar_container_ userInterfaceLayoutDirection] ==
            NSUserInterfaceLayoutDirectionRightToLeft;
  show_on_hover_ = NO;
  mouse_inside_ = NO;
  window_ = window->GetNativeWindow().GetNativeNSWindow();

  NSButton* button = [window_ standardWindowButton:NSWindowCloseButton];
  // Safety check just in case apple changes the view structure in a macOS
  // upgrade.
  if (!button.superview || !button.superview.superview) {
    NOTREACHED() << "macOS has changed its window buttons view structure.";
    titlebar_container_ = nullptr;
    return self;
  }
  titlebar_container_ = button.superview.superview;

  // Remember the default margin.
  margin_ = default_margin_ = [self getCurrentMargin];
  return self;
}

- (void)dealloc {
  if (hover_view_)
    [hover_view_ removeFromSuperview];
  [super dealloc];
}

- (void)setVisible:(BOOL)visible {
  if (!titlebar_container_)
    return;
  [titlebar_container_ setHidden:!visible];
}

- (void)setShowOnHover:(BOOL)yes {
  if (!titlebar_container_)
    return;
  show_on_hover_ = yes;
  // Put a transparent view above the window buttons so we can track mouse
  // events when mouse enter/leave the window buttons.
  if (show_on_hover_) {
    hover_view_.reset([[ButtonsAreaHoverView alloc] initWithProxy:self]);
    [hover_view_ setFrame:[self getHoverViewBounds]];
    [titlebar_container_ addSubview:hover_view_.get()];
  } else {
    [hover_view_ removeFromSuperview];
    hover_view_.reset();
  }
  [self updateButtonsVisibility];
}

- (void)setMargin:(const absl::optional<gfx::Point>&)margin {
  if (margin)
    margin_ = *margin;
  else
    margin_ = default_margin_;
  [self redraw];
}

- (NSRect)getButtonsContainerBounds {
  NSButton* left;
  NSButton* right;
  if (is_rtl_) {
    left = [window_ standardWindowButton:NSWindowZoomButton];
    right = [window_ standardWindowButton:NSWindowCloseButton];
  } else {
    left = [window_ standardWindowButton:NSWindowCloseButton];
    right = [window_ standardWindowButton:NSWindowZoomButton];
  }

  float x = is_rtl_ ? NSMinX(left.frame) : 0;
  float y = NSMinY(left.frame) - margin_.y();
  float width = NSMaxX(right.frame) - NSMinX(left.frame) + margin_.x();
  float height = NSHeight(left.frame) + 2 * margin_.y();
  return NSMakeRect(x, y, width, height);
}

- (NSRect)getHoverViewBounds {
  NSRect rect = [self getButtonsContainerBounds];
  float x = is_rtl_ ? NSMinX(rect) : margin_.x();
  return NSMakeRect(x, margin_.y(), NSWidth(rect) - margin_.x(),
                    NSHeight(rect) - 2 * margin_.y());
}

- (void)redraw {
  if (!titlebar_container_)
    return;

  NSButton* close_button = [window_ standardWindowButton:NSWindowCloseButton];
  NSButton* minimize_button =
      [window_ standardWindowButton:NSWindowMiniaturizeButton];
  NSButton* zoom_button = [window_ standardWindowButton:NSWindowZoomButton];

  CGRect rect = titlebar_container_.frame;
  rect.size.height = NSHeight(close_button.frame) + 2 * margin_.y();
  rect.origin.y = NSHeight(window_.frame) - NSHeight(rect);
  [titlebar_container_ setFrame:rect];

  const CGFloat space_between =
      NSMinX(minimize_button.frame) - NSMinX(close_button.frame);
  NSArray* buttons = @[ close_button, minimize_button, zoom_button ];
  for (NSUInteger i = 0; i < buttons.count; i++) {
    NSView* view = [buttons objectAtIndex:i];
    NSRect button_rect = view.frame;
    if (is_rtl_) {
      button_rect.origin.x = NSWidth(rect) - margin_.x() + (i * space_between) -
                             NSWidth(button_rect);
    } else {
      button_rect.origin.x = margin_.x() + (i * space_between);
    }
    button_rect.origin.y = (NSHeight(rect) - NSHeight(button_rect)) / 2;
    [view setFrameOrigin:button_rect.origin];
  }

  if (hover_view_)
    [hover_view_ setFrame:[self getHoverViewBounds]];
}

- (void)updateTrackingAreas {
  if (tracking_area_)
    [hover_view_ removeTrackingArea:tracking_area_.get()];
  tracking_area_.reset([[NSTrackingArea alloc]
      initWithRect:NSZeroRect
           options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways |
                   NSTrackingInVisibleRect
             owner:self
          userInfo:nil]);
  [hover_view_ addTrackingArea:tracking_area_.get()];
}

- (void)mouseEntered:(NSEvent*)event {
  mouse_inside_ = YES;
  [self updateButtonsVisibility];
}

- (void)mouseExited:(NSEvent*)event {
  mouse_inside_ = NO;
  [self updateButtonsVisibility];
}

- (void)updateButtonsVisibility {
  NSArray* buttons = @[
    [window_ standardWindowButton:NSWindowCloseButton],
    [window_ standardWindowButton:NSWindowMiniaturizeButton],
    [window_ standardWindowButton:NSWindowZoomButton],
  ];
  // Show buttons when mouse hovers above them.
  BOOL hidden = show_on_hover_ && !mouse_inside_;
  // Always show buttons under fullscreen.
  if ([window_ styleMask] & NSWindowStyleMaskFullScreen) {
    hidden = NO;
    LOG(ERROR) << "NO hidden";
  }
  for (NSView* button in buttons) {
    [button setHidden:hidden];
    [button setNeedsDisplay:YES];
  }
}

// Compute margin from position of current buttons.
- (gfx::Point)getCurrentMargin {
  gfx::Point result;
  if (!titlebar_container_)
    return result;

  NSButton* close_button = [window_ standardWindowButton:NSWindowCloseButton];
  result.set_y(
      (NSHeight(titlebar_container_.frame) - NSHeight(close_button.frame)) / 2);

  if (is_rtl_) {
    NSButton* button = [window_ standardWindowButton:NSWindowZoomButton];
    result.set_x(NSWidth(titlebar_container_.frame) - NSMinX(button.frame) +
                 NSWidth(button.frame));
  } else {
    result.set_x(NSMinX(close_button.frame));
  }
  return result;
}

@end
