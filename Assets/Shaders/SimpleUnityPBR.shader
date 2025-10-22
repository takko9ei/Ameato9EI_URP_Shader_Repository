Shader "Custom/SimpleUnityPBR"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Tint("base color tint",Color) = (1,1,1,1)
        [Gamma]_Metallic("Metallic",range(0,1)) = 0
        _Smoothness("test smoothness",Range(0,1)) = 0
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

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            #ifndef PI
                #define PI 3.14159265359
                #define INV_PI 0.3183099
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
                float3 worldViewDir : TEXCOORD2;
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float _Metallic;
                half4 _Tint;
                half _Smoothness;
            CBUFFER_END

            inline half DisneyDiffuse(half NdotV, half NdotL, half LdotH, half perceptualRoughness)
            {
                half fd90 = 0.5 + 2 * LdotH * LdotH * perceptualRoughness;
                // Two schlick fresnel term
                half lightScatter   = (1 + (fd90 - 1) * pow(1 - NdotL,5));
                half viewScatter    = (1 + (fd90 - 1) * pow(1 - NdotV,5));
                return lightScatter * viewScatter;
            }

            inline half GGXTerm (half NdotH, half roughness)
            {
                half a2 = roughness * roughness;
                half d = (NdotH * a2 - NdotH) * NdotH + 1.0f; // 2 mad
                return INV_PI * a2 / (d * d + 1e-7f);//avoid devide 0
            }

            inline half SmithJointGGXVisibilityTerm (half NdotL, half NdotV, half roughness)
            {
                half a = roughness;
                half lambdaV = NdotL * (NdotV * (1 - a) + a);
                half lambdaL = NdotV * (NdotL * (1 - a) + a);
                return 0.5f / (lambdaV + lambdaL + 1e-5f);
            }

            inline half3 FresnelTerm(half3 F0,half cosA)
            {
                half t=pow(1-cosA,5);// ala Schlick interpoliation
                return F0+(1-F0)*t;
            }

            inline half3 FresnelLerp(half3 F0,half3 F90,half cosA)
            {
            half t = pow(1-cosA,5);
            return lerp(F0,F90,t);
            }

            inline half OneMinusReflectivityFromMetallic(half metallic)
            {
                // We'll need oneMinusReflectivity, so
                //   1-reflectivity = 1-lerp(dielectricSpec, 1, metallic) = lerp(1-dielectricSpec, 0, metallic)
                // store (1-dielectricSpec) in unity_ColorSpaceDielectricSpec.a, then
                //   1-reflectivity = lerp(alpha, 0, metallic) = alpha + metallic*(0 - alpha) =
                //                  = alpha - metallic * alpha
                half oneMinusDielectricSpec = kDielectricSpec.w;
                return oneMinusDielectricSpec - metallic * oneMinusDielectricSpec;
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex.xyz);
                o.uv = v.uv;
                o.worldNormal = normalize(o.worldNormal = mul(v.normal,(float3x3)unity_WorldToObject));
                o.worldViewDir = GetCameraPositionWS()-TransformObjectToWorld(v.vertex.xyz);
                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                i.worldNormal = normalize(i.worldNormal);
                Light mainLight = GetMainLight();
                half3 lightDir = normalize(mainLight.direction);
                half3 viewDir = normalize(i.worldViewDir);
                half3 halfVector = normalize(lightDir+viewDir);
                half3 worldRefl = reflect(-i.worldViewDir, i.worldNormal);

                half smoothness = _Smoothness;
                half roughness = 1-smoothness;
                half sqRoughness = roughness * roughness;
                sqRoughness = max(0.012,sqRoughness);
                half fpRoughness = sqRoughness * sqRoughness;

                half nl = max(saturate(dot(i.worldNormal, lightDir)), 0.000001);
	            half nv = max(saturate(dot(i.worldNormal, viewDir)), 0.000001);
	            half vh = max(saturate(dot(viewDir, halfVector)), 0.000001);
	            half lh = max(saturate(dot(lightDir, halfVector)), 0.000001);
	            half nh = max(saturate(dot(i.worldNormal, halfVector)), 0.000001);

                half3 baseColor = SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,i.uv).xyz * _Tint;

                half3 dDiffResult = 0;
	            half3 dSpecResult = 0;
                half D = GGXTerm(nh,sqRoughness);
                half G = SmithJointGGXVisibilityTerm(nl,nv,sqRoughness);
                half3 F0 = lerp(kDielectricSpec.xyz, baseColor, _Metallic);
                half3 F = FresnelTerm(F0,lh);
                float3 kd = baseColor*OneMinusReflectivityFromMetallic(_Metallic);
                dDiffResult = kd * DisneyDiffuse(nv,nl,lh,roughness)*nl*mainLight.color;
                dSpecResult = D*G*F*mainLight.color*nl*PI;//denominator in G
                half3 directResult = dDiffResult + dSpecResult;

                half3 idDiffResult = 0;
	            half3 idSpecResult = 0;
                half3 iblDiffuse = SampleSH(i.worldNormal);
				idDiffResult = iblDiffuse*kd;
                float mip_roughness = roughness * (1.7 - 0.7*roughness);
				//float3 reflectVec = reflect(-viewDir, normal);
				half mip = mip_roughness * UNITY_SPECCUBE_LOD_STEPS;//得出mip层级。默认UNITY_SPECCUBE_LOD_STEPS=6（定义在UnityStandardConfig.cginc）
				half4 rgbm = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0,worldRefl, mip);//视线方向的反射向量，去取样，同时考虑mip层级
				float3 iblSpecular = DecodeHDREnvironment(rgbm, unity_SpecCube0_HDR);//使用DecodeHDR将颜色从HDR编码下解码。可以看到采样出的rgbm是一个4通道的值，
				half surfaceReduction=1.0/(fpRoughness+1.0);
				float oneMinusReflectivity = OneMinusReflectivityFromMetallic(_Metallic);	//grazingTerm压暗非金属的边缘异常高亮
				half grazingTerm=saturate(smoothness+(1-oneMinusReflectivity));
				idSpecResult = surfaceReduction*iblSpecular*FresnelLerp(F0,grazingTerm,nv);
	            half3 indirectResult = idDiffResult + idSpecResult;

                half3 lightResult = directResult + indirectResult;

                return half4(dSpecResult,1);
            }   
            ENDHLSL
        }
    }
}
