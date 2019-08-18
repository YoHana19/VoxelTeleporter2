Shader "Geometry/VoxelTeleporter2"
{
    Properties
    {
		[Header(Cell Parameters)]
		_Density("Density", Range(0.0, 1.0)) = 0.05
		_CellSize("CellSize", Range(0.0, 1.0)) = 0.08
		
		[Header(Animation)]
		_Inflation("Inflation", Range(1.0, 20.0)) = 16.0
		_Swirling("Swirling", Range(0.0, 5.0)) = 2.0
		_Scatter("Scatter", Range(1.0, 10.0)) = 4.0

		[Header(Rendering)]
		_MainTex("Texture", 2D) = "white" {}
		[HDR] _EmissionColor("EmissionColor", Color) = (0, 0, 0, 0)
		[HDR] _EdgeColor("EdgeColor", Color) = (0, 0, 0, 0)
		_EdgeWidth("EdgeWidth", Range(0.0, 10.0)) = 1
		_HueShift("HueShift", Range(0.0, 1.0)) = 0.015
		_Highlight("Highlight", Range(0.0, 1.0)) = 0.2
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
		Cull Off
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
			#pragma geometry geom
            #pragma fragment frag
            #include "UnityCG.cginc"
			#include "VoxelTeleporter2.cginc"
            ENDCG
        }
    }
}
