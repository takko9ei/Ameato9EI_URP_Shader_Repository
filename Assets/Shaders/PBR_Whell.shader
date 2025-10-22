Shader "Custom/PBR_Whell"
{
    Properties
    {
        _MainColor("main color",Color) = (1,1,1,1)
        _MainTex("main texture",2D) = "white"{}
        _Smoothness("smoothness",Range(0,1)) = 1.0
        [Gamma]_Metallic("metallic",Range(0,1)) = 1.0
        _IblLut("IBL LUT",2D) = "white"{}
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline"}
        LOD 100

        Pass
        {
            Tags { "LightMode"="UniversalForward"}
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdbase

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma shader_feature _AdditionalLights
            
            // make fog work
            //#pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"

            #ifndef _AdditionalLights
                #define _AdditionalLights
            #endif
            #ifndef PI
                #define PI 3.14159265359
            #endif

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 worldNormal : TEXCOORD1;
                float3 objectNormal : TEXCOORD2;
                float3 worldViewDir : TEXCOORD3;
                float3 objectViewDir : TEXCOORD4;
                float3 worldPos : TEXCOORD5;
                float3 worldRefl : TEXCOORD6;
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            TEXTURE2D(_IblLut);
            SAMPLER(sampler_IblLut);

            //CBUFFER_START(UnityPerMaterial)
                float _Metallic;
                float _Smoothness;
                float4 _MainColor;
            //CBUFFER_END

            float3 fresnelSchlickRoughness(float cosTheta, float3 F0, float roughness)
            {
                return F0 + (max(float3(1 ,1, 1) * (1 - roughness), F0) - F0) * pow(1.0 - cosTheta, 5.0);
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex.xyz);
                o.uv = v.uv;
                o.worldNormal = mul(v.normal,(float3x3)unity_WorldToObject);
                o.objectNormal = v.normal;
                o.worldPos = TransformObjectToWorld(v.vertex.xyz);
                o.worldViewDir = GetCameraPositionWS()-o.worldPos;
                o.objectViewDir = TransformWorldToObject(GetCameraPositionWS())-v.vertex;
                o.worldRefl = reflect(-o.worldViewDir, o.worldNormal);
                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                float4 shadowCoord = TransformWorldToShadowCoord(i.worldPos);
				Light mainLight = GetMainLight(shadowCoord);
                i.worldNormal = normalize(i.worldNormal);
				half3 lightDir = normalize(mainLight.direction);
				half3 ambient = SampleSH(i.worldNormal);
                half3 viewDir = normalize(i.worldViewDir);
                half3 halfVector = normalize(lightDir+viewDir);
                half3 worldRefl = reflect(-i.worldViewDir,i.worldNormal);
                
                half smoothness = _Smoothness;
                half roughness = 1-smoothness;
                half sqRoughness = roughness * roughness;
                half fpRoughness = sqRoughness * sqRoughness;

                float nl = max(saturate(dot(i.worldNormal, lightDir)), 0.000001);
	            float nv = max(saturate(dot(i.worldNormal, viewDir)), 0.000001);
	            float vh = max(saturate(dot(viewDir, halfVector)), 0.000001);
	            float lh = max(saturate(dot(lightDir, halfVector)), 0.000001);
	            float nh = max(saturate(dot(i.worldNormal, halfVector)), 0.000001);
                

                half shadow = MainLightRealtimeShadow(shadowCoord);
                half atten = mainLight.distanceAttenuation;
                half3 baseColor = SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,i.uv)*_MainColor;

                half3 diffColor = 0;
	            half3 specColor = 0;
                //float Kd = 1;
                
                //lambert
                //diffColor = Kd*baseColor*mainLight.color.rgb*nl;
                
                half lerpSquareRoughness = pow(lerp(0.002, 1, sqRoughness), 2);                                     //Unity把roughness lerp到了0.002
                half D = lerpSquareRoughness / (pow((pow(nh, 2) * (lerpSquareRoughness - 1) + 1), 2) * PI);   //ndf Trowbridge-Reitz GGX, D
                half kInDirectLight = pow(fpRoughness + 1, 2) / 8;
                half kInIBL = pow(fpRoughness, 2) / 8;
                half GLight = nl / lerp(nl, 1, kInDirectLight);
                half GView = nv / lerp(nv, 1, kInDirectLight);
                half G = GLight * GView;
                half3 F0 = lerp(kDielectricSpec.xyz, baseColor, _Metallic);
                half3 F = F0 + (1 - F0) * exp2((-5.55473 * vh - 6.98316) * vh);                                     //approximate fresnel
                specColor = (D * G * F * 0.25) / (nv * nl);
                float3 Kd = (1 - F)*(1 - _Metallic);
                diffColor = Kd*baseColor*mainLight.color.rgb*nl;
	            half3 DirectLightResult = diffColor + specColor;

                float3 idDiffResult = 0;
	            float3 idSpecResult = 0;

                float3 baseContribution = 0.03 * baseColor;//idk y add this
                float3 iblDiffuse = max(half3(0, 0, 0), baseContribution.rgb + ambient);

                float mip_roughness = roughness * (1.7 - 0.7 * roughness);


                half mip = mip_roughness * UNITY_SPECCUBE_LOD_STEPS;
                half4 rgbm = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0,worldRefl, mip); 
                float3 iblSpecular = DecodeHDREnvironment(rgbm, unity_SpecCube0_HDR);

                float2 envBDRF = SAMPLE_TEXTURE2D(_IblLut,sampler_IblLut,float2(lerp(0, 0.99, nv), lerp(0, 0.99, sqRoughness))).rg;


                float3 Flast = fresnelSchlickRoughness(max(nv, 0.0), F0, sqRoughness);
				float kdLast = (1 - Flast) * (1 - _Metallic);

				idDiffResult = iblDiffuse * kdLast * baseColor;
				idSpecResult = iblSpecular * (Flast * envBDRF.r + envBDRF.g);
                float3 IndirectResult = idDiffResult + idSpecResult;

                return half4(DirectLightResult+IndirectResult,1);
            }
            ENDHLSL
        }
        
    }
}