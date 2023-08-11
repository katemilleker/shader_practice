
// Example Pixel Shader

// FORCES
uniform vec3 uExternalForce;
uniform vec3 uKeyboardForce;
uniform samplerBuffer aAttractorTransAndRad;
uniform int uNumAttractors;
uniform float uAttractMag;

// WORLD
uniform vec3 uWorldBoundsMin;
uniform vec3 uWorldBoundsMax;

// PARTICLES
uniform int uParticleCount;
uniform vec2 uLifeExpectancy;
uniform vec4 uStartColor;
uniform vec4 uEndColor;
uniform float uMaxSpeed;
uniform float uAbsMaxSteerForce;
uniform float uMass;
uniform vec2 uScaleAndScaleVariance;

// TOUCH
uniform float uTimeTick;

#define POS_AND_SCALE 0
#define COLOR 1
#define VELOCITY 2
#define EMIT_TRANSFORM 3
#define EMIT_NORMAL 4
#define RANDOM 5
#define EXTERNAL_FORCE 6
#define LIFE 7

out layout (location=0) vec4 oPositionAndScale;
out layout (location=1) vec4 oColor;
out layout (location=2) vec3 oVelocity;
out layout (location=3) vec4 oLife;

struct Particle{
	vec3 position;
	vec4 color;
	float scale;
	vec3 velocity;
	vec3 acceleration;
	float life;
};

vec2 Random(){
	return texture(sTD2DInputs[RANDOM], vUV.st).rg;
}

float map(float value, float inLo, float inHi, float outLo, float outHi){
	return outLo + (value - inLo) * (outHi - outLo) / (inHi - inLo);
}

void ApplyForce(inout Particle p, vec3 force){
	p.acceleration += force / uMass;
}

void SeekTarget(inout Particle p, vec3 target, float mag, float rad){
	vec3 desired = target - p.position;

	float dist = length(desired);
	desired = normalize(desired);
	if( dist < rad ){
		float m = map(dist, 0, rad, 0, uMaxSpeed);
		desired *= m;
	} else {
		desired *= uMaxSpeed;
	}

	vec3 steer = desired - p.velocity;
	steer = clamp(steer, vec3(-uAbsMaxSteerForce), vec3(uAbsMaxSteerForce));

	ApplyForce(p, steer * mag);
}

void Attractors(inout Particle p){
	for(int i=0; i < uNumAttractors; i++){
		vec4 attractor = texelFetchBuffer(aAttractorTransAndRad, i);
		SeekTarget(p, attractor.xyz, uAttractMag, attractor.w);
	}

}

vec3 NormalizedPos(Particle p){
	// returns a normalized position using uniform world bounds
	vec3 worldSize = uWorldBoundsMax - uWorldBoundsMin;
	vec3 normPos = (p.position-uWorldBoundsMin) / worldSize;
	return normPos;
}

void SetColor(inout Particle p){
	float f = p.life / uLifeExpectancy.x;
	vec4 color = mix(uEndColor, uStartColor, f);
	p.color = color;
}

int Index(){
	vec2 wh = uTD2DInfos[0].res.zw;
	vec2 coord = vec2(floor(gl_FragCoord.x),floor(gl_FragCoord.y));
	return int(coord.x + (coord.y * wh.x));
}

bool Active(){
	return Index() < uParticleCount;
}


void Spawn(inout Particle p){
	float u = Random().x;
	vec2 lookup = vec2(u, 0.5);
	p.position = texture(sTD2DInputs[EMIT_TRANSFORM], lookup).xyz;
	p.velocity = texture(sTD2DInputs[EMIT_NORMAL], lookup).xyz;
	p.acceleration = vec3(0);
	p.life = max(0, uLifeExpectancy.x - (uLifeExpectancy.y * Random().x));
	p.scale = uScaleAndScaleVariance.x + uScaleAndScaleVariance.y * Random().x;
}

Particle Read(vec2 uv){
	Particle p;
	p.acceleration = vec3(0);
	vec4 posAndScale = texture(sTD2DInputs[POS_AND_SCALE], uv);
	p.position = posAndScale.xyz;
	p.scale = posAndScale.w;
	p.color = texture(sTD2DInputs[COLOR], uv);
	p.velocity = texture(sTD2DInputs[VELOCITY], uv).xyz;
	p.life = texture(sTD2DInputs[LIFE], uv).x;
	return p;
}

void Write(Particle p, vec2 uv){
	oPositionAndScale = vec4(p.position, p.scale);
	oColor = p.color;
	oVelocity = p.velocity;
	oLife = vec4(p.life,0,0,0);
}

bool OutOfBounds(Particle p){
	return p.position.x < uWorldBoundsMin.x ||
		   p.position.x > uWorldBoundsMax.x ||
		   p.position.y < uWorldBoundsMin.y ||
		   p.position.y > uWorldBoundsMax.y ||
		   p.position.z < uWorldBoundsMin.z ||
		   p.position.z > uWorldBoundsMax.z;
}

void Update(inout Particle p){
	p.life -= uTimeTick;
	if(OutOfBounds(p) || p.life <= 0){
		Spawn(p);
		return;
	}
	p.velocity += p.acceleration;
	p.position += p.velocity;
	p.acceleration = vec3(0);
}

void main()
{
	Particle p = Read(vUV.st);
	if(Active()){
		ApplyForce(p, uExternalForce);
		ApplyForce(p, uKeyboardForce);
		ApplyForce(p, texture(sTD2DInputs[EXTERNAL_FORCE], NormalizedPos(p).xy).xyz);
		Attractors(p);
		SetColor(p);
		Update(p);
	} else {
		p.position = vec3(-9999999, -99999999, -9999999);
	}

	Write(p, vUV.st);
}
