shader_type canvas_item;
// 契約切れ (残り使用回数 0) のカードから色を抜き、灰のように暗くする。
// COLOR は絵の色と頂点の色を掛けた値で渡ってくる

// 灰にした後の明るさの倍率。色を抜いただけでは羊皮紙の明るさが残り、色のあるカードより目立つため沈める
// (0.72 は、沈めても名前と効果の墨の文字が読める明るさ)
const float BRIGHTNESS = 0.72;

void fragment() {
	// 係数は輝度の重み (ITU-R BT.601)
	COLOR.rgb = vec3(dot(COLOR.rgb, vec3(0.299, 0.587, 0.114)) * BRIGHTNESS);
}
