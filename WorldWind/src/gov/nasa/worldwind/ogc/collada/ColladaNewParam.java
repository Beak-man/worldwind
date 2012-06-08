/*
 * Copyright (C) 2012 United States Government as represented by the Administrator of the
 * National Aeronautics and Space Administration.
 * All Rights Reserved.
 */

package gov.nasa.worldwind.ogc.collada;

/**
 * Represents the Collada <i>Newparam</i> element and provides access to its contents.
 *
 * @author pabercrombie
 * @version $Id$
 */
public class ColladaNewParam extends ColladaAbstractObject
{
    public ColladaNewParam(String ns)
    {
        super(ns);
    }

    public ColladaSampler2D getSampler2D()
    {
        return (ColladaSampler2D) this.getField("sampler2D");
    }

    public ColladaSurface getSurface()
    {
        return (ColladaSurface) this.getField("surface");
    }
}