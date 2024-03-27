#ifdef VERTEX

uniform mat4 modelToScreen;

vec4 position(mat4 loveTransform, vec4 vertexPosModel) {
	return modelToScreen * vertexPosModel;
}

#endif

#ifdef PIXEL

uniform bool fade;

vec4 effect(vec4 colour, sampler2D image, vec2 textureCoords, vec2 windowCoords) {
	if (!fade) {
		return colour;
	}

	vec2 textureCoordsNewRange = textureCoords * 2.0 - 1.0;
	float fadeAmount = max(1.0 - length(textureCoordsNewRange), 0.0);
	return colour * fadeAmount;
}

#endif
