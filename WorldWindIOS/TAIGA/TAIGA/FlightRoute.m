/*
 Copyright (C) 2013 United States Government as represented by the Administrator of the
 National Aeronautics and Space Administration. All Rights Reserved.

 @version $Id$
 */

#import <CoreLocation/CoreLocation.h>
#import "FlightRoute.h"
#import "AircraftShape.h"
#import "Waypoint.h"
#import "AppConstants.h"
#import "WorldWind/Geometry/WWBoundingSphere.h"
#import "WorldWind/Geometry/WWPosition.h"
#import "WorldWind/Geometry/WWVec4.h"
#import "WorldWind/Layer/WWLayer.h"
#import "WorldWind/Render/WWDrawContext.h"
#import "Worldwind/Shapes/WWPath.h"
#import "WorldWind/Shapes/WWShapeAttributes.h"
#import "WorldWind/Shapes/WWSphere.h"
#import "WorldWind/Terrain/WWGlobe.h"
#import "WorldWind/Util/WWColor.h"
#import "WorldWind/Util/WWMath.h"
#import "WorldWind/WorldWindConstants.h"
#import "WorldWind/WWLog.h"

const float PathWidth = 4.0;
const double WaypointRadius = 6.0;
const double WaypointMinRadius = 20.0;
const double WaypointMaxRadius = 20000.0;
const double WaypointPickRadius = 22.0;
const double ArrowSize = 24;
const double ArrowMinSize = 40.0;
const double ArrowMaxSize = 100000.0;

@implementation FlightRoute

+ (NSArray*) flightRouteColors
{
    static NSArray* colors = nil;
    if (colors == nil)
    {
        colors = @[
                @{@"color" : [[WWColor alloc] initWithR:1.000 g:0.035 b:0.329 a:1.0], @"displayName" : @"Red"},
                @{@"color" : [[WWColor alloc] initWithR:1.000 g:0.522 b:0.000 a:1.0], @"displayName" : @"Orange"},
                @{@"color" : [[WWColor alloc] initWithR:1.000 g:0.776 b:0.000 a:1.0], @"displayName" : @"Yellow"},
                @{@"color" : [[WWColor alloc] initWithR:0.310 g:0.851 b:0.129 a:1.0], @"displayName" : @"Green"},
                @{@"color" : [[WWColor alloc] initWithR:0.027 g:0.596 b:0.976 a:1.0], @"displayName" : @"Blue"},
                @{@"color" : [[WWColor alloc] initWithR:0.757 g:0.325 b:0.863 a:1.0], @"displayName" : @"Purple"}
        ];
    }

    return colors;
}

- (id) initWithDisplayName:(NSString*)displayName colorIndex:(NSUInteger)colorIndex defaultAltitude:(double)defaultAltitude
{
    if (displayName == nil)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Display name is nil")
    }

    self = [super init];

    _displayName = displayName;
    _enabled = YES;
    _colorIndex = colorIndex;
    _defaultAltitude = defaultAltitude;

    waypoints = [[NSMutableArray alloc] initWithCapacity:8];
    [self initShapes];

    return self;
}

- (id) initWithPropertyList:(NSDictionary*)propertyList
{
    if (propertyList == nil)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Property list is nil")
    }

    self = [super init];

    _displayName = [propertyList objectForKey:@"displayName"];
    _enabled = [[propertyList objectForKey:@"enabled"] boolValue];
    _colorIndex = [[propertyList objectForKey:@"colorIndex"] unsignedIntegerValue];
    _defaultAltitude = [[propertyList objectForKey:@"defaultAltitude"] doubleValue];

    NSArray* waypointPropertyLists = [propertyList objectForKey:@"waypoints"];
    waypoints = [[NSMutableArray alloc] initWithCapacity:[waypointPropertyLists count]];

    for (NSDictionary* waypointPropertyList in waypointPropertyLists)
    {
        Waypoint* waypoint = [[Waypoint alloc] initWithPropertyList:waypointPropertyList];
        [waypoints addObject:waypoint];
    }

    [self initShapes];

    return self;
}

- (NSDictionary*) asPropertyList
{
    NSMutableArray* waypointPropertyLists = [NSMutableArray arrayWithCapacity:[waypoints count]];
    for (Waypoint* waypoint in waypoints)
    {
        [waypointPropertyLists addObject:[waypoint asPropertyList]];
    }

    return @{
        @"displayName" : _displayName,
        @"enabled" : [NSNumber numberWithBool:_enabled],
        @"colorIndex" : [NSNumber numberWithUnsignedInteger:_colorIndex],
        @"defaultAltitude" : [NSNumber numberWithDouble:_defaultAltitude],
        @"waypoints" : waypointPropertyLists
    };
}

- (void) initShapes
{
    NSDictionary* colorAttrs = [[FlightRoute flightRouteColors] objectAtIndex:_colorIndex];
    WWColor* color = [colorAttrs objectForKey:@"color"];

    pathAttrs = [[WWShapeAttributes alloc] init];
    [pathAttrs setOutlineColor:color];
    [pathAttrs setOutlineWidth:PathWidth];

    shapeAttrs = [[WWShapeAttributes alloc] init];
    [shapeAttrs setInteriorColor:color];
    [shapeAttrs setOutlineEnabled:NO];

    waypointPositions = [[NSMutableArray alloc] initWithCapacity:[waypoints count]];
    waypointShapes = [[NSMutableArray alloc] initWithCapacity:[waypoints count]];
    arrowShapes = [[NSMutableArray alloc] initWithCapacity:[waypoints count] > 0 ? [waypoints count] - 1 : 0];
    currentPosition = [[WWPosition alloc] initWithZeroPosition];

    for (Waypoint* waypoint in waypoints)
    {
        WWPosition* pos = [[WWPosition alloc] initWithDegreesLatitude:[waypoint latitude] longitude:[waypoint longitude] altitude:[waypoint altitude]];
        [waypointPositions addObject:pos];

        id shape = [self createWaypointShapeWithPosition:pos];
        [waypointShapes addObject:shape];
    }

    waypointPath = [self createPathWithPositions:waypointPositions];
}

- (WWPath*) createPathWithPositions:(NSArray*)positions
{
    WWPath* path = [[WWPath alloc] initWithPositions:positions];
    [path setAttributes:pathAttrs];
    [path setPathType:WW_RHUMB];
    [path setNumSubsegments:100];
    [path setPickDelegate:@{@"flightRoute":self}];

    return path;
}

- (id) createWaypointShapeWithPosition:(WWPosition*)position
{
    WWSphere* shape = [[WWSphere alloc] initWithPosition:position radiusInPixels:WaypointRadius minRadius:WaypointMinRadius maxRadius:WaypointMaxRadius];
    [shape setAttributes:shapeAttrs];

    return shape;
}

- (id) createArrowShapeWithPosition:(WWPosition*)position heading:(double)heading legLength:(double)legLength
{
    AircraftShape* shape = [[AircraftShape alloc] initWithSizeInPixels:ArrowSize minSize:ArrowMinSize maxSize:MIN(ArrowMaxSize, legLength / 2.0)];
    [shape setAttributes:shapeAttrs];
    [shape setPosition:position];
    [shape setHeading:heading];

    return shape;
}

- (void) updateWaypointShape:(id)shape withPosition:(WWPosition*)position
{
    [(WWSphere*) shape setPosition:position];
}

- (void) setDisplayName:(NSString*)displayName
{
    _displayName = displayName;

    [self didChangeAttribute];
}

- (void) setEnabled:(BOOL)enabled
{
    _enabled = enabled;

    [self didChangeAttribute];
}

- (void) setColorIndex:(NSUInteger)colorIndex
{
    _colorIndex = colorIndex;

    NSDictionary* colorAttrs = [[FlightRoute flightRouteColors] objectAtIndex:_colorIndex];
    WWColor* color = [colorAttrs objectForKey:@"color"];
    [pathAttrs setOutlineColor:color];
    [shapeAttrs setInteriorColor:color];

    [self didChangeAttribute];
}

- (void) setDefaultAltitude:(double)defaultAltitude
{
    _defaultAltitude = defaultAltitude;

    [self didChangeAttribute];
}

- (void) render:(WWDrawContext*)dc
{
    if (!_enabled)
    {
        return;
    }

    [waypointPath render:dc];

    if (![dc pickingMode])
    {
        [self drawArrows:dc];
    }

    [self drawWaypoints:dc];
}

- (void) drawArrows:(WWDrawContext*)dc
{
    if ([arrowShapes count] == 0 && [waypointPositions count] > 1)
    {
        WWGlobe* globe = [dc globe];
        double globeRadius = MAX([globe equatorialRadius], [globe polarRadius]);

        for (NSUInteger i = 0; i < [waypointPositions count] - 1; i++)
        {
            WWPosition* begin = [waypointPositions objectAtIndex:i];
            WWPosition* end = [waypointPositions objectAtIndex:i + 1];

            double azimuth = [WWLocation rhumbAzimuth:begin endLocation:end];
            double distance = [WWLocation rhumbDistance:begin endLocation:end];
            double distanceMeters = RADIANS(distance) * globeRadius;
            WWPosition* pos = [[WWPosition alloc] init];
            [WWLocation rhumbLocation:begin azimuth:azimuth distance:0.5 * distance outputLocation:pos];
            [pos setAltitude:[WWMath interpolateValue1:[begin altitude] value2:[end altitude] amount:0.5]];

            id shape = [self createArrowShapeWithPosition:pos heading:azimuth legLength:distanceMeters];
            [arrowShapes addObject:shape];
        }
    }

    for (id shape in arrowShapes)
    {
        [shape render:dc];
    }
}

- (void) drawWaypoints:(WWDrawContext*)dc
{
    NSUInteger index = 0;
    for (id shape in waypointShapes)
    {
        double originalRadius = [shape radius];
        if ([dc pickingMode])
        {
            [shape setRadius:WaypointPickRadius];
            [shape setPickDelegate:@{@"flightRoute":self, @"waypointIndex":[NSNumber numberWithUnsignedInteger:index]}];
        }

        [shape render:dc];

        if ([dc pickingMode])
        {
            [shape setRadius:originalRadius];
        }

        index++;
    }
}

- (id <WWExtent>) extentOnGlobe:(WWGlobe*)globe;
{
    if (globe == nil)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Globe is nil")
    }

    if ([waypoints count] == 0)
        return nil;

    NSMutableArray* waypointPoints = [[NSMutableArray alloc] initWithCapacity:[waypoints count]];
    for (Waypoint* waypoint in waypoints)
    {
        WWVec4* point = [[WWVec4 alloc] initWithZeroVector];
        [globe computePointFromPosition:[waypoint latitude] longitude:[waypoint longitude] altitude:[waypoint altitude] outputPoint:point];
        [waypointPoints addObject:point];
    }

    return [[WWBoundingSphere alloc] initWithPoints:waypointPoints];
}

- (void) locationForPercent:(double)pct
                   latitude:(CLLocationDegrees*)latitude
                  longitude:(CLLocationDegrees*)longitude
                   altitude:(CLLocationDistance*)altitude
                     course:(CLLocationDirection*)course
{
    if (pct < 0 || pct > 1)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Percent is invalid")
    }

    NSUInteger waypointCount = [waypointPositions count];
    if (waypointCount == 1)
    {
        WWPosition* pos = [waypointPositions firstObject];
        *latitude = [pos latitude];
        *longitude = [pos longitude];
        *altitude = [pos altitude];
        *course = 0;
    }
    else // if (waypointCount > 1)
    {
        double legDistance[waypointCount - 1];
        double routeDistance = 0;

        NSUInteger i;
        for (i = 0; i < waypointCount - 1; i++)
        {
            WWPosition* begin = [waypointPositions objectAtIndex:i];
            WWPosition* end = [waypointPositions objectAtIndex:i + 1];
            legDistance[i] = [WWLocation rhumbDistance:begin endLocation:end];
            routeDistance += legDistance[i];
        }

        double pctDistance = pct * routeDistance;
        double remainingDistance = pctDistance;

        for (i = 0; i < waypointCount - 1; i++)
        {
            if (remainingDistance < legDistance[i]) // location is within this non-zero length leg
            {
                double legPct = remainingDistance / legDistance[i];
                WWPosition* begin = [waypointPositions objectAtIndex:i];
                WWPosition* end = [waypointPositions objectAtIndex:i + 1];
                [WWPosition rhumbInterpolate:begin endPosition:end amount:legPct outputPosition:currentPosition];
                *latitude = [currentPosition latitude];
                *longitude = [currentPosition longitude];
                *altitude = [currentPosition altitude];
                *course = [self convertAzimuthToCourse:[WWPosition rhumbAzimuth:currentPosition endLocation:end]]; // convert from [-180,180] to [0,360]
                return;
            }

            remainingDistance -= legDistance[i];
        }

        // location is at the last waypoint
        WWPosition* begin = [waypointPositions objectAtIndex:i - 1];
        WWPosition* end = [waypointPositions objectAtIndex:i];
        *latitude = [end latitude];
        *longitude = [end longitude];
        *altitude = [end altitude];
        *course = [self convertAzimuthToCourse:[WWPosition rhumbAzimuth:begin endLocation:end]]; // convert from [-180,180] to [0,360]
    }
}

- (CLLocationDirection) convertAzimuthToCourse:(double)degreesAzimuth
{
    return (degreesAzimuth < 0) ? 360 + degreesAzimuth : degreesAzimuth;
}

- (NSUInteger) waypointCount
{
    return [waypoints count];
}

- (Waypoint*) waypointAtIndex:(NSUInteger)index
{
    if (index >= [waypoints count])
    {
        NSString* msg = [[NSString alloc] initWithFormat:@"Index %d is out of range", index];
        WWLOG_AND_THROW(NSInvalidArgumentException, msg)
    }

    return [waypoints objectAtIndex:index];
}

- (NSUInteger) indexOfWaypoint:(Waypoint*)waypoint
{
    if (waypoint == nil)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Waypoint is nil")
    }

    return [waypoints indexOfObject:waypoint];
}

- (void) insertWaypoint:(Waypoint*)waypoint atIndex:(NSUInteger)index
{
    if (waypoint == nil)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Waypoint is nil")
    }

    if (index > [waypoints count])
    {
        NSString* msg = [[NSString alloc] initWithFormat:@"Index %d is out of range", index];
        WWLOG_AND_THROW(NSInvalidArgumentException, msg)
    }

    WWPosition* pos = [[WWPosition alloc] initWithDegreesLatitude:[waypoint latitude] longitude:[waypoint longitude] altitude:[waypoint altitude]];
    id shape = [self createWaypointShapeWithPosition:pos];

    [waypoints insertObject:waypoint atIndex:index];
    [waypointPositions insertObject:pos atIndex:index];
    [waypointShapes insertObject:shape atIndex:index];
    [waypointPath setPositions:waypointPositions];

    [self didInsertWaypointAtIndex:index];
}

- (void) removeWaypointAtIndex:(NSUInteger)index
{
    if (index >= [waypoints count])
    {
        NSString* msg = [[NSString alloc] initWithFormat:@"Index %d is out of range", index];
        WWLOG_AND_THROW(NSInvalidArgumentException, msg)
    }

    [waypoints removeObjectAtIndex:index];
    [waypointPositions removeObjectAtIndex:index];
    [waypointShapes removeObjectAtIndex:index];
    [waypointPath setPositions:waypointPositions];

    [self didRemoveWaypointAtIndex:index];
}

- (void) replaceWaypointAtIndex:(NSUInteger)index withWaypoint:(Waypoint*)newWaypoint
{
    if (index >= [waypoints count])
    {
        NSString* msg = [[NSString alloc] initWithFormat:@"Index %d is out of range", index];
        WWLOG_AND_THROW(NSInvalidArgumentException, msg)
    }

    if (newWaypoint == nil)
    {
        WWLOG_AND_THROW(NSInvalidArgumentException, @"Waypoint is nil")
    }

    WWPosition* pos = [waypointPositions objectAtIndex:index];
    [pos setDegreesLatitude:[newWaypoint latitude] longitude:[newWaypoint longitude] altitude:[newWaypoint altitude]];

    id shape = [waypointShapes objectAtIndex:index];
    [self updateWaypointShape:shape withPosition:pos];

    [waypoints replaceObjectAtIndex:index withObject:newWaypoint];
    [waypointPath setPositions:waypointPositions];

    [self didReplaceWaypointAtIndex:index];
}

- (void) moveWaypointAtIndex:(NSUInteger)fromIndex toIndex:(NSUInteger)toIndex
{
    if (fromIndex >= [waypoints count])
    {
        NSString* msg = [[NSString alloc] initWithFormat:@"From index %d is out of range", fromIndex];
        WWLOG_AND_THROW(NSInvalidArgumentException, msg)
    }

    if (toIndex >= [waypoints count])
    {
        NSString* msg = [[NSString alloc] initWithFormat:@"To index %d is out of range", toIndex];
        WWLOG_AND_THROW(NSInvalidArgumentException, msg)
    }

    Waypoint* waypoint = [waypoints objectAtIndex:fromIndex];
    [waypoints removeObjectAtIndex:fromIndex];
    [waypoints insertObject:waypoint atIndex:toIndex];

    id pos = [waypointPositions objectAtIndex:fromIndex];
    [waypointPositions removeObjectAtIndex:fromIndex];
    [waypointPositions insertObject:pos atIndex:toIndex];
    [waypointPath setPositions:waypointPositions];

    id shape = [waypointShapes objectAtIndex:fromIndex];
    [waypointShapes removeObjectAtIndex:fromIndex];
    [waypointShapes insertObject:shape atIndex:toIndex];

    [self didMoveWaypointFromIndex:fromIndex toIndex:toIndex];
}

- (void) reverseWaypoints
{
    NSArray* reversedWaypoints = [[waypoints reverseObjectEnumerator] allObjects];
    NSArray* reversedPositions = [[waypointPositions reverseObjectEnumerator] allObjects];
    NSArray* reversedShapes = [[waypointShapes reverseObjectEnumerator] allObjects];

    NSRange allObjects = NSMakeRange(0, [waypoints count]);
    [waypoints replaceObjectsInRange:allObjects withObjectsFromArray:reversedWaypoints];
    [waypointPositions replaceObjectsInRange:allObjects withObjectsFromArray:reversedPositions];
    [waypointShapes replaceObjectsInRange:allObjects withObjectsFromArray:reversedShapes];
    [waypointPath setPositions:waypointPositions];

    [self didReverseWaypoints];
}

- (void) didChangeAttribute
{
    [[NSNotificationCenter defaultCenter] postNotificationName:TAIGA_FLIGHT_ROUTE_ATTRIBUTE_CHANGED object:self];
}

- (void) didInsertWaypointAtIndex:(NSUInteger)index
{
    [arrowShapes removeAllObjects];
    [[NSNotificationCenter defaultCenter] postNotificationName:TAIGA_FLIGHT_ROUTE_WAYPOINT_INSERTED object:self
                                                      userInfo:@{TAIGA_FLIGHT_ROUTE_WAYPOINT_INDEX : [NSNumber numberWithUnsignedInteger:index]}];
}

- (void) didRemoveWaypointAtIndex:(NSUInteger)index
{
    [arrowShapes removeAllObjects];
    [[NSNotificationCenter defaultCenter] postNotificationName:TAIGA_FLIGHT_ROUTE_WAYPOINT_REMOVED object:self
                                                      userInfo:@{TAIGA_FLIGHT_ROUTE_WAYPOINT_INDEX : [NSNumber numberWithUnsignedInteger:index]}];
}

- (void) didReplaceWaypointAtIndex:(NSUInteger)index
{
    [arrowShapes removeAllObjects];
    [[NSNotificationCenter defaultCenter] postNotificationName:TAIGA_FLIGHT_ROUTE_WAYPOINT_REPLACED object:self
                                                      userInfo:@{TAIGA_FLIGHT_ROUTE_WAYPOINT_INDEX : [NSNumber numberWithUnsignedInteger:index]}];
}

- (void) didMoveWaypointFromIndex:(NSUInteger)fromIndex toIndex:(NSUInteger)toIndex
{
    [arrowShapes removeAllObjects];
    [[NSNotificationCenter defaultCenter] postNotificationName:TAIGA_FLIGHT_ROUTE_WAYPOINT_MOVED object:self
                                                      userInfo:@{TAIGA_FLIGHT_ROUTE_WAYPOINT_INDEX : [NSNumber numberWithUnsignedInteger:toIndex]}];
}

- (void) didReverseWaypoints
{
    [arrowShapes removeAllObjects];
    [[NSNotificationCenter defaultCenter] postNotificationName:TAIGA_FLIGHT_ROUTE_ALL_WAYPOINTS_CHANGED object:self];
}

@end