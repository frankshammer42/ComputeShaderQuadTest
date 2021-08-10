const float pi = 3.14159;
const float pi2 = 3.14159 * 2.;

struct ParticleData
{
	float3 velocity;
	float3 position;
	float3 acceleration;
	float2 shrinkExtends;
	float3 originPosition;
	float2 texCoords;
	float freq;
};

StructuredBuffer<ParticleData> _ParticleBuffer;

float2x2 rot2D(float r)
{
	float c = cos(r), s = sin(r);
	return float2x2(c, s, -s, c);
}

float nsin(float a){return .5+.5*sin(a);}

float ncos(float a){return .5+.5*cos(a);}

float3 saturate(float3 a){return clamp(a,0.,1.);}

float opS( float d2, float d1 ){return max(-d1,d2);}

float rand(float2 co){
	return frac(sin(dot(co.xy ,float2(12.9898,78.233))) * 43758.5453);
}

float rand(float n){
	return frac(cos(n*89.42)*343.42);
}
float dtoa(float d, float amount)
{
	return clamp(1.0 / (clamp(d, 1.0/amount, 1.0)*amount), 0.,1.);
}

float sdAxisAlignedRect(float2 uv, float2 tl, float2 br)
{
	float2 d = max(tl-uv, uv-br);
	return length(max(float2(0.0, 0.0), d)) + min(0.0, max(d.x, d.y));
}

// 0-1 1-0
float smoothstep4(float e1, float e2, float e3, float e4, float val)
{
	return min(smoothstep(e1,e2,val), 1.-smoothstep(e3,e4,val));
}

// hash & simplex noise from https://www.shadertoy.com/view/Msf3WH
float2 hash( float2 p )
{
	p = float2( dot(p,float2(127.1,311.7)),
			  dot(p,float2(269.5,183.3)) );
	return -1.0 + 2.0*frac(sin(p)*43758.5453123);
}
// returns -.5 to 1.5. i think.
float noise( in float2 p )
{
	const float K1 = 0.366025404; // (sqrt(3)-1)/2;
	const float K2 = 0.211324865; // (3-sqrt(3))/6;

	float2 i = floor( p + (p.x+p.y)*K1 );
	
	float2 a = p - i + (i.x+i.y)*K2;
	float2 o = (a.x>a.y) ? float2(1.0,0.0) : float2(0.0,1.0); //float2 of = 0.5 + 0.5*float2(sign(a.x-a.y), sign(a.y-a.x));
	float2 b = a - o + K2;
	float2 c = a - 1.0 + 2.0*K2;

	float3 h = max( 0.5-float3(dot(a,a), dot(b,b), dot(c,c) ), 0.0 );

	float3 n = h*h*h*h*float3( dot(a,hash(i+0.0)), dot(b,hash(i+o)), dot(c,hash(i+1.0)));

	return dot( n, float3(70.0, 70.0, 70.0) );	
}

float noise01(float2 p)
{
	return clamp((noise(p)+.5)*.5, 0.,1.);
}

float3 colorAxisAlignedBrushStroke(float2 uv, float2 uvPaper, float3 inpColor, float4 brushColor, float2 p1, float2 p2, float timeChangeScale)
{
	
	// how far along is this point in the line. will come in handy.
	float2 posInLine = smoothstep(p1, p2, uv);//(uv-p1)/(p2-p1);

	// wobble it around, humanize
	float wobbleAmplitude = 0.13;
	uv.x += sin(posInLine.y * pi2 * 0.2) * wobbleAmplitude;

	// distance to geometry
	float d = sdAxisAlignedRect(uv, p1, float2(p1.x, p2.y));
	d -= abs(p1.x - p2.x) * 0.5;// rounds out the end.

	// warp the position-in-line, to control the curve of the brush falloff.
	float _brushExtensionFreq = 1.0;
	posInLine = pow(posInLine, float2(nsin(timeChangeScale * _brushExtensionFreq * _Time.y) * 2. + 0.3, nsin(timeChangeScale * _brushExtensionFreq * _Time.y) * 2.) + 0.3);

	// brush stroke fibers effect.
	float strokeStrength = dtoa(d, 100.);
	float strokeAlpha = 0.
		+ noise01((p2-uv) * float2(min(_ScreenParams.y,_ScreenParams.x)*0.25, 1.))// high freq fibers
		+ noise01((p2-uv) * float2(79., 1.))// smooth brush texture. lots of room for variation here, also layering.
		+ noise01((p2-uv) * float2(14., 1.))// low freq noise, gives more variation
		;
	strokeAlpha *= 0.66;
	strokeAlpha = strokeAlpha * strokeStrength;
	strokeAlpha = strokeAlpha - (1.-posInLine.y);
	strokeAlpha = (1.-posInLine.y) - (strokeAlpha * (1.-posInLine.y));

	// fill texture. todo: better curve, more round?
	const float inkOpacity = 0.85;
	float fillAlpha = (dtoa(abs(d), 90.) * (1.-inkOpacity)) + inkOpacity;

	// todo: splotches ?
	
	// paper bleed effect.
	float amt = 140. + (rand(uvPaper.y) * 30.) + (rand(uvPaper.x) * 30.);
	

	float alpha = fillAlpha * strokeAlpha * brushColor.a * dtoa(d, amt);
	alpha = clamp(alpha, 0.,1.);
	return lerp(inpColor, brushColor.rgb, alpha);
}

float3 colorBrushStroke(float2 uv, float3 inpColor, float4 brushColor, float2 p1, float2 p2, float lineWidth, float timeChangeScale)
{
	// flatten the line to be axis-aligned.
	float2 rectDimensions = p2 - p1;
	float angle = atan2(rectDimensions.y, rectDimensions.x);
	float2x2 rotMat = rot2D(-angle);
	p1 = mul(p1, rotMat);
	p2 = mul(p2, rotMat);
	float halfLineWidth = lineWidth / 2.;
	p1 -= halfLineWidth;
	p2 += halfLineWidth;
	float3 ret = colorAxisAlignedBrushStroke(mul(uv, rotMat), uv, inpColor, brushColor, p1, p2, timeChangeScale);
	return ret;
}

float circle(in float2 _st, in float _radius){
	float dist = _st-float2(0.5, 0.5);
	return 1.0 - smoothstep(_radius-(_radius*0.01),
						 _radius+(_radius*0.01),
						 dot(dist,dist)*4.0);
}

float2 antialias(float radius, float borderSize, float dist)
{
	float t = smoothstep(radius + borderSize, radius - borderSize, dist);
	return t;
}

float4 generateBrushColorWithFreq(float2 inputUV, float freq)
{
	float2 uv = inputUV - 1.0;
	//float3 col = float3(0.8, 0.8, 0.0);
	float3 col = float3(0.0, 0.0, 0.0);
	float randScale = 14.0;
	col = colorBrushStroke(uv, col, float4(float3(1., 1., 1.), 1.0),// black fixed line
				   float2(0.0, -1.0),
				   float2(0.0, 1.0),
				   _Time.y *  freq * randScale, freq );
	col.rgb += (rand(uv)-.5)*.08;
	float finalColor = max(0.5 - length((inputUV - float2(0.5, 0.5))), 0.0);
	col.rgb *= finalColor; 
	float4 currentColor = float4(col.rgb, finalColor);
	return currentColor;
}

float4 generateBrushColor(float2 inputUV)
{
		float2 uv = inputUV - 1.0;
		//float3 col = float3(0.8, 0.8, 0.0);
		float3 col = float3(0.0, 0.0, 0.0);
		float randScale = 14.0;
		col = colorBrushStroke(uv, col, float4(float3(1., 1., 1.), 1.0),// black fixed line
					   float2(0.0, -1.0),
					   float2(0.0, 1.0),
					   _Time.y * 10.0 * randScale, randScale);
		col.rgb += (rand(uv)-.5)*.08;
		float finalColor = max(0.5 - length((inputUV - float2(0.5, 0.5))), 0.0);
		col.rgb *= finalColor; 
		float4 currentColor = float4(col.rgb, finalColor);
		return currentColor;
}


void SpeedLineGFrag(  PackedVaryingsToPS packedInput,
            OUTPUT_GBUFFER(outGBuffer)
            #ifdef _DEPTHOFFSET_ON
            , out float outputDepth : SV_Depth
            #endif
            )
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(packedInput);
    FragInputs input = UnpackVaryingsMeshToFragInputs(packedInput.vmesh);

    // input.positionSS is SV_Position
    PositionInputs posInput = GetPositionInput(input.positionSS.xy, _ScreenSize.zw, input.positionSS.z, input.positionSS.w, input.positionRWS);

#ifdef VARYINGS_NEED_POSITION_WS
    float3 V = GetWorldSpaceNormalizeViewDir(input.positionRWS);
#else
    // Unused
    float3 V = float3(1.0, 1.0, 1.0); // Avoid the division by 0
#endif

    SurfaceData surfaceData;
    BuiltinData builtinData;
    GetSurfaceAndBuiltinData(input, V, posInput, surfaceData, builtinData);
	float2 uv = input.texCoord0.xy;
	float4 brushColor = generateBrushColor(uv);
	surfaceData.baseColor = brushColor;  
	

    ENCODE_INTO_GBUFFER(surfaceData, builtinData, posInput.positionSS, outGBuffer);

#ifdef _DEPTHOFFSET_ON
    outputDepth = posInput.deviceDepth;
#endif
}

//TODO: WHERE THE FUCK are the documentations for this things fuck 
struct SpeedLineAttributes
{
	uint vertexID : SV_VertexID;
	UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct CustomPackedVaryingsToPS
{
	nointerpolation float brushFreq: COLOR3; 
#ifdef VARYINGS_NEED_PASS
    PackedVaryingsPassToPS vpass;
#endif
    PackedVaryingsMeshToPS vmesh;
    UNITY_VERTEX_OUTPUT_STEREO
};

CustomPackedVaryingsToPS PackCustom(VaryingsToPS input, float freq)
{
    CustomPackedVaryingsToPS output;
	output.brushFreq = freq;
    output.vmesh = PackVaryingsMeshToPS(input.vmesh);
#ifdef VARYINGS_NEED_PASS
    output.vpass = PackVaryingsPassToPS(input.vpass);
#endif
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
    return output;
}

float4 SpeedLineFragWithFreq(CustomPackedVaryingsToPS packedInput) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(packedInput);
    FragInputs input = UnpackVaryingsMeshToFragInputs(packedInput.vmesh);

    // input.positionSS is SV_Position
    PositionInputs posInput = GetPositionInput(input.positionSS.xy, _ScreenSize.zw, input.positionSS.z, input.positionSS.w, input.positionRWS);

#ifdef VARYINGS_NEED_POSITION_WS
    float3 V = GetWorldSpaceNormalizeViewDir(input.positionRWS);
#else
    // Unused
    float3 V = float3(1.0, 1.0, 1.0); // Avoid the division by 0
#endif

    SurfaceData surfaceData;
    BuiltinData builtinData;
    GetSurfaceAndBuiltinData(input, V, posInput, surfaceData, builtinData);

    // Not lit here (but emissive is allowed)
    BSDFData bsdfData = ConvertSurfaceDataToBSDFData(input.positionSS.xy, surfaceData);
	float2 uv = input.texCoord0.xy;
	float4 brushColor = generateBrushColorWithFreq(uv, packedInput.brushFreq);
    float4 outColor = ApplyBlendMode(brushColor + builtinData.emissiveColor * GetCurrentExposureMultiplier(), builtinData.opacity);
	outColor.w = brushColor.w;
    // Note: we must not access bsdfData in shader pass, but for unlit we make an exception and assume it should have a color field
    //outColor = EvaluateAtmosphericScattering(posInput, V, outColor);

#ifdef DEBUG_DISPLAY
    // Same code in ShaderPassForward.shader
    // Reminder: _DebugViewMaterialArray[i]
    //   i==0 -> the size used in the buffer
    //   i>0  -> the index used (0 value means nothing)
    // The index stored in this buffer could either be
    //   - a gBufferIndex (always stored in _DebugViewMaterialArray[1] as only one supported)
    //   - a property index which is different for each kind of material even if reflecting the same thing (see MaterialSharedProperty)
    int bufferSize = int(_DebugViewMaterialArray[0]);
    // Loop through the whole buffer
    // Works because GetSurfaceDataDebug will do nothing if the index is not a known one
    for (int index = 1; index <= bufferSize; index++)
    {
        int indexMaterialProperty = int(_DebugViewMaterialArray[index]);
        if (indexMaterialProperty != 0)
        {
            float3 result = float3(1.0, 0.0, 1.0);
            bool needLinearToSRGB = false;

            GetPropertiesDataDebug(indexMaterialProperty, result, needLinearToSRGB);
            GetVaryingsDataDebug(indexMaterialProperty, input, result, needLinearToSRGB);
            GetBuiltinDataDebug(indexMaterialProperty, builtinData, result, needLinearToSRGB);
            GetSurfaceDataDebug(indexMaterialProperty, surfaceData, result, needLinearToSRGB);
            GetBSDFDataDebug(indexMaterialProperty, bsdfData, result, needLinearToSRGB);
            
            // TEMP!
            // For now, the final blit in the backbuffer performs an sRGB write
            // So in the meantime we apply the inverse transform to linear data to compensate.
            if (!needLinearToSRGB)
                result = SRGBToLinear(max(0, result));

            outColor = float4(result, 1.0);
        }
    }

    if (_DebugFullScreenMode == FULLSCREENDEBUGMODE_TRANSPARENCY_OVERDRAW)
    {
        float4 result = _DebugTransparencyOverdrawWeight * float4(TRANSPARENCY_OVERDRAW_COST, TRANSPARENCY_OVERDRAW_COST, TRANSPARENCY_OVERDRAW_COST, TRANSPARENCY_OVERDRAW_A);
        outColor = result;
    }

#endif
	
	return brushColor; 
}

CustomPackedVaryingsToPS SpeedLineVertWithFreq(SpeedLineAttributes input)
{
	uint id = input.vertexID;
	AttributesMesh inputMesh;
	inputMesh.positionOS = _ParticleBuffer[id].position;
	#ifdef ATTRIBUTES_NEED_NORMAL
	inputMesh.normalOS = float3(0.0,0.0,-1.0);
	#endif
	#ifdef ATTRIBUTES_NEED_TANGENT
	inputMesh.tangentOS = float4(1.0,0.0,0.0,1.0);
	#endif
	#ifdef ATTRIBUTES_NEED_TEXCOORD0
	inputMesh.uv0 =  _ParticleBuffer[id].texCoords;
	#endif
	#ifdef ATTRIBUTES_NEED_TEXCOORD1
	inputMesh.uv1 = 0;
	#endif
	#ifdef ATTRIBUTES_NEED_TEXCOORD2
	inputMesh.uv2 = 0;
	#endif
	#ifdef ATTRIBUTES_NEED_TEXCOORD3
	inputMesh.uv3 = 0;
	#endif
	#ifdef ATTRIBUTES_NEED_COLOR
	inputMesh.color = 0;
	#endif
	UNITY_TRANSFER_INSTANCE_ID(input, inputMesh);
	
    VaryingsType varyingsType;
    varyingsType.vmesh = VertMesh(inputMesh);
    return PackCustom(varyingsType, _ParticleBuffer[id].freq);
}


PackedVaryingsType SpeedLineVert(SpeedLineAttributes input)
{
	uint id = input.vertexID;
	AttributesMesh inputMesh;
	inputMesh.positionOS = _ParticleBuffer[id].position;
	#ifdef ATTRIBUTES_NEED_NORMAL
	inputMesh.normalOS = float3(0.0,0.0,-1.0);
	#endif
	#ifdef ATTRIBUTES_NEED_TANGENT
	inputMesh.tangentOS = float4(1.0,0.0,0.0,1.0);
	#endif
	#ifdef ATTRIBUTES_NEED_TEXCOORD0
	inputMesh.uv0 =  _ParticleBuffer[id].texCoords;
	#endif
	#ifdef ATTRIBUTES_NEED_TEXCOORD1
	inputMesh.uv1 = 0;
	#endif
	#ifdef ATTRIBUTES_NEED_TEXCOORD2
	inputMesh.uv2 = 0;
	#endif
	#ifdef ATTRIBUTES_NEED_TEXCOORD3
	inputMesh.uv3 = 0;
	#endif
	#ifdef ATTRIBUTES_NEED_COLOR
	inputMesh.color = 0;
	#endif
	UNITY_TRANSFER_INSTANCE_ID(input, inputMesh);
	
    VaryingsType varyingsType;
    varyingsType.vmesh = VertMesh(inputMesh);
    return PackVaryingsType(varyingsType);
}

float4 SpeedLineFrag(PackedVaryingsToPS packedInput) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(packedInput);
    FragInputs input = UnpackVaryingsMeshToFragInputs(packedInput.vmesh);

    // input.positionSS is SV_Position
    PositionInputs posInput = GetPositionInput(input.positionSS.xy, _ScreenSize.zw, input.positionSS.z, input.positionSS.w, input.positionRWS);

#ifdef VARYINGS_NEED_POSITION_WS
    float3 V = GetWorldSpaceNormalizeViewDir(input.positionRWS);
#else
    // Unused
    float3 V = float3(1.0, 1.0, 1.0); // Avoid the division by 0
#endif

    SurfaceData surfaceData;
    BuiltinData builtinData;
    GetSurfaceAndBuiltinData(input, V, posInput, surfaceData, builtinData);

    // Not lit here (but emissive is allowed)
    BSDFData bsdfData = ConvertSurfaceDataToBSDFData(input.positionSS.xy, surfaceData);
	float2 uv = input.texCoord0.xy;
	float4 brushColor = generateBrushColor(uv);
    float4 outColor = ApplyBlendMode(brushColor + builtinData.emissiveColor * GetCurrentExposureMultiplier(), builtinData.opacity);
	outColor.w = brushColor.w;
    // Note: we must not access bsdfData in shader pass, but for unlit we make an exception and assume it should have a color field
    //outColor = EvaluateAtmosphericScattering(posInput, V, outColor);

#ifdef DEBUG_DISPLAY
    // Same code in ShaderPassForward.shader
    // Reminder: _DebugViewMaterialArray[i]
    //   i==0 -> the size used in the buffer
    //   i>0  -> the index used (0 value means nothing)
    // The index stored in this buffer could either be
    //   - a gBufferIndex (always stored in _DebugViewMaterialArray[1] as only one supported)
    //   - a property index which is different for each kind of material even if reflecting the same thing (see MaterialSharedProperty)
    int bufferSize = int(_DebugViewMaterialArray[0]);
    // Loop through the whole buffer
    // Works because GetSurfaceDataDebug will do nothing if the index is not a known one
    for (int index = 1; index <= bufferSize; index++)
    {
        int indexMaterialProperty = int(_DebugViewMaterialArray[index]);
        if (indexMaterialProperty != 0)
        {
            float3 result = float3(1.0, 0.0, 1.0);
            bool needLinearToSRGB = false;

            GetPropertiesDataDebug(indexMaterialProperty, result, needLinearToSRGB);
            GetVaryingsDataDebug(indexMaterialProperty, input, result, needLinearToSRGB);
            GetBuiltinDataDebug(indexMaterialProperty, builtinData, result, needLinearToSRGB);
            GetSurfaceDataDebug(indexMaterialProperty, surfaceData, result, needLinearToSRGB);
            GetBSDFDataDebug(indexMaterialProperty, bsdfData, result, needLinearToSRGB);
            
            // TEMP!
            // For now, the final blit in the backbuffer performs an sRGB write
            // So in the meantime we apply the inverse transform to linear data to compensate.
            if (!needLinearToSRGB)
                result = SRGBToLinear(max(0, result));

            outColor = float4(result, 1.0);
        }
    }

    if (_DebugFullScreenMode == FULLSCREENDEBUGMODE_TRANSPARENCY_OVERDRAW)
    {
        float4 result = _DebugTransparencyOverdrawWeight * float4(TRANSPARENCY_OVERDRAW_COST, TRANSPARENCY_OVERDRAW_COST, TRANSPARENCY_OVERDRAW_COST, TRANSPARENCY_OVERDRAW_A);
        outColor = result;
    }

#endif
	
	return brushColor; 
}
