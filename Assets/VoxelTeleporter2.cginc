#ifndef VoxelTeleporter2_INCLUDED
#define VoxelTeleporter2_INCLUDED

#include "Common.cginc"
#include "SimplexNoise3D.hlsl"

sampler2D _MainTex;
float4 _MainTex_ST;
float _Density;
float _CellSize;
float _Inflation;
float _Swirling;
float _Scatter;
float _Highlight;

float4 _EffectVector;
float3 _EffectOrigin;

struct appdata
{
	float4 vertex: POSITION;
	float2 uv: TEXCOORD0;
};

struct g2f
{
	float4 vertex: SV_POSITION;
	float2 uv: TEXCOORD0;
	float4 colorParams: TEXCOORD1;
};

appdata vert(appdata v)
{
	v.vertex = mul(unity_ObjectToWorld, v.vertex);
	return v;
}

// Cell animation function that calculates quad vertex positions and normal
// vector from a given triangle and parameters.
void CellAnimation(
	uint primitiveID, float param,
	// Input: triangle vertices and centroid
	float3 p_t0, float3 p_t1, float3 p_t2,
	// Output: quad positions and normal vector
	out float3 p_q0, out float3 p_q1, out float3 p_q2, out float3 p_q3, out float3 n_q
)
{

	// Triangle inflation (only visible at the beginning of the animation)
	float inflation = 1 + _Inflation * smoothstep(0, 0.2, param);
	float3 center = (p_t0 + p_t1 + p_t2) / 3;
	p_t0 = lerp(center, p_t0, inflation);
	p_t1 = lerp(center, p_t1, inflation);
	p_t2 = lerp(center, p_t2, inflation);

	// Relative position of the primitive center from the effector origin.
	float3 p_rel = center - _EffectOrigin;

	// Swirling animation
	float swirl = smoothstep(0, 2, param) * 2;     // Ease-in, steep-out
	swirl *= lerp(-1, 1, Random(primitiveID * 367)); // Random distribution
	swirl *= _Swirling / (length(p_rel.xz) + 1e-5); // Cancelling differences

	// Apply swirling animation to the relative position.
	float2 sc = float2(sin(swirl), cos(swirl));
	p_rel.xz = mul(float2x2(sc.y, -sc.x, sc.x, sc.y), p_rel.xz);

	// Tangent space reconstruction
	float3 tan_y = float3(0, 1, 0);
	float3 tan_z = normalize(float3(p_rel.x, 0, p_rel.z));
	float3 tan_x = normalize(cross(tan_y, tan_z));

	// Size of the output quad
	float size = _CellSize * (1 - smoothstep(0.8, 1, param)); // Ease-out
	size *= lerp(0.5, 1, Random(primitiveID * 701));           // 50% random

	// Reconstruct the cell center from the relative position.
	float scatter = _Scatter * Random(primitiveID * 131); // Random distribution
	scatter = 1 + scatter * smoothstep(0.1, 1, param); // Ease-in/out
	float3 p_qc = float3(p_rel.xz * scatter, p_rel.y).xzy + _EffectOrigin;

	// Triangle to quad transformation
	half t2q = smoothstep(0, 0.2, param);
	p_q0 = lerp(p_t0, p_qc + (-tan_x - tan_y) * size, t2q);
	p_q1 = lerp(p_t1, p_qc + (+tan_x - tan_y) * size, t2q);
	p_q2 = lerp(p_t2, p_qc + (-tan_x + tan_y) * size, t2q);
	p_q3 = lerp(p_t2, p_qc + (+tan_x + tan_y) * size, t2q);

	// Normal vector recalculation
	n_q = normalize(cross(p_q1 - p_q0, p_q2 - p_q0));
}

g2f VertexOutput(float3 wpos, float2 uv, half emission = 0, half random = 0, half2 qcoord = -1)
{
	g2f o;
	o.vertex = UnityWorldToClipPos(float4(wpos, 1));
	o.uv = uv;
	o.colorParams = float4(qcoord, emission, random);
	return o;
}

[maxvertexcount(4)]
void geom(triangle appdata input[3], uint pid: SV_PrimitiveID, inout TriangleStream<g2f> outStream)
{
	float3 p0 = input[0].vertex.xyz;
	float3 p1 = input[1].vertex.xyz;
	float3 p2 = input[2].vertex.xyz;
	float3 center = (p0 + p1 + p2) / 3;

	float2 uv0 = input[0].uv;
	float2 uv1 = input[1].uv;
	float2 uv2 = input[2].uv;
	float2 uv = (uv0 + uv1 + uv2) / 3;

	float param = dot(_EffectVector.xyz, center) - _EffectVector.w;
	float random = lerp(1, 1.25, Random(pid * 761)); // 25% distribution
	param = saturate(param * random);

	// Pass through the vertices if the animation hasn't been started.
	if (param == 0)
	{
		outStream.Append(VertexOutput(p0, uv0));
		outStream.Append(VertexOutput(p1, uv1));
		outStream.Append(VertexOutput(p2, uv2));
		outStream.RestartStrip();
		return;
	}

	// Random selection
	if (Random(pid * 877) > _Density)
	{
		// Not selected: Simple scaling during [0.05, 0.1]
		param = smoothstep(0.05, 0.1, param);
		p0 = lerp(p0, center, param);
		p1 = lerp(p1, center, param);
		p2 = lerp(p2, center, param);

		outStream.Append(VertexOutput(p0, uv0, param));
		outStream.Append(VertexOutput(p1, uv1, param));
		outStream.Append(VertexOutput(p2, uv2, param));
		outStream.RestartStrip();
		return;
	}

	// Cell animation
	float3 p_q0, p_q1, p_q2, p_q3, n_q;
	CellAnimation(
		pid, param, p0, p1, p2,
		p_q0, p_q1, p_q2, p_q3, n_q
	);

	// Self emission parameter (0:off -> 1:emission -> 2:edge)
	float intensity = smoothstep(0.05, 0.1, param) + smoothstep(0.1, 0.2, param);
	// Pick some cells and stop their animation at 1.0 to highlight them.
	intensity = min(intensity, Random(pid * 329) < _Highlight ? 1 : 2);

	half rand = Random(pid * 227);
	outStream.Append(VertexOutput(p_q0, uv, intensity, rand, half2(0, 0)));
	outStream.Append(VertexOutput(p_q1, uv, intensity, rand, half2(1, 0)));
	outStream.Append(VertexOutput(p_q2, uv, intensity, rand, half2(0, 1)));
	outStream.Append(VertexOutput(p_q3, uv, intensity, rand, half2(1, 1)));
	outStream.RestartStrip();
}

half4 _EmissionColor;
half4 _EdgeColor;
half _EdgeWidth;
half _HueShift;

// Self emission term (effect emission + edge detection)
half3 SelfEmission(half4 colorParams)
{
	half2 quad = colorParams.xy; // for edge detection
	half intensity = colorParams.z; // 0:off -> 1:emission -> 2:edge
	half random = colorParams.w;

	// Edge detection
	half2 edge2 = min(quad, 1 - quad) > fwidth(quad) * _EdgeWidth;
	half edge = (1 - min(edge2.x, edge2.y)) * (quad.x >= 0);

	// Random hue shift
	half hueShift = (random - 0.5) * 2 * _HueShift;

	// Emission color
	fixed4 hsl = RGB2HSL(_EmissionColor);
	half3 c1 = HSL2RGB(half4(hsl.x + hueShift, hsl.yzw));
	c1 *= _EmissionColor.w * saturate(intensity);

	// Edge color
	fixed4 hslEdge = RGB2HSL(_EdgeColor);
	half3 c2 = HSL2RGB(half4(hslEdge.x + hueShift, hslEdge.yzw));
	c2 *= edge * _EdgeColor.w;

	return lerp(c1, c2, saturate(intensity - 1));
}

fixed4 frag(g2f i) : SV_Target
{
	fixed4 col = tex2D(_MainTex, i.uv);
	col.xyz += SelfEmission(i.colorParams);
	return col;
}
#endif