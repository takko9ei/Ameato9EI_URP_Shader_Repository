Shader "Unlit/BasicLighting"
{
    Properties
    {
        _MainCol ("col", Color) = (1,1,1,1)
        _Gloss("gl",Float) = 1.0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag


            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

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

            float4 _MainCol;
            float _Gloss;

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
                // sample the texture
                half3 col = _MainCol.xyz;
                i.worldNormal = normalize(i.worldNormal);
                Light mainLight = GetMainLight();
                half3 lightDir = normalize(mainLight.direction);
                half3 viewDir = normalize(i.worldViewDir);
                half3 halfVector = normalize(lightDir+viewDir);
                half3 worldRefl = reflect(-i.worldViewDir, i.worldNormal);

                half3 diff;
                half3 spec;
                half3 ambdiff;
                half3 ambspec;

                diff = dot(i.worldNormal,lightDir)*mainLight.color*col;
                ambdiff = SampleSH(i.worldNormal);
                spec = pow(saturate(dot(halfVector,i.worldNormal)),_Gloss)*mainLight.color*col;

                // apply fog
                return half4(spec,1);
            }
            ENDHLSL
        }
    }
}
