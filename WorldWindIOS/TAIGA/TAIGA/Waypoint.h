/*
 Copyright (C) 2013 United States Government as represented by the Administrator of the
 National Aeronautics and Space Administration. All Rights Reserved.

 @version $Id$
 */

#import <Foundation/Foundation.h>

@class WWLocation;

typedef enum
{
    WaypointTypeAirport,
    WaypointTypeMarker
} WaypointType;

@interface Waypoint : NSObject

@property (nonatomic, readonly) NSString* key;

@property (nonatomic, readonly) WWLocation* location;

@property (nonatomic, readonly) WaypointType type;

@property (nonatomic, readonly) NSString* iconPath;

@property (nonatomic, readonly) UIImage* iconImage;

@property (nonatomic) NSString* displayName;

@property (nonatomic) NSDictionary* properties;

- (id) initWithKey:(NSString*)key location:(WWLocation*)location type:(WaypointType)type;

- (id) initWithWaypointTableRow:(NSDictionary*)values;

- (id) initWithDegreesLatitude:(double)latitude longitude:(double)longitude;

- (id) initWithPropertyList:(NSDictionary*)propertyList;

- (NSDictionary*) propertyList;

@end