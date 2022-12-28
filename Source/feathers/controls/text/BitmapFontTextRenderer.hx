/*
	Feathers
	Copyright 2012-2020 Bowler Hat LLC. All Rights Reserved.

	This program is free software. You can redistribute and/or modify it in
	accordance with the terms of the accompanying license agreement.
 */

package feathers.controls.text;

import starling.utils.MathUtil;
import starling.utils.Pool;
import openfl.text.TextFormatAlign;
import openfl.geom.Point;
import starling.rendering.Painter;
import starling.display.Image;
import starling.text.BitmapFont;
import starling.styles.MeshStyle;
import feathers.core.FeathersControl;
import starling.text.TextFormat;
import feathers.text.BitmapFontTextFormat;
import starling.display.MeshBatch;
import feathers.skins.IStyleProvider;
import starling.text.BitmapChar;
import feathers.core.ITextRenderer;

/**
 * Renders text using
 * <a href="http://wiki.starling-framework.org/manual/displaying_text#bitmap_fonts" target="_top">bitmap fonts</a>.
 *
 * <p>The following example shows how to use
 * <code>BitmapFontTextRenderer</code> with a <code>Label</code>:</p>
 *
 * <listing version="3.0">
 * var label:Label = new Label();
 * label.text = "I am the very model of a modern Major General";
 * label.textRendererFactory = function():ITextRenderer
 * {
 *     return new BitmapFontTextRenderer();
 * };
 * this.addChild( label );</listing>
 *
 * @see ../../../../help/text-renderers.html Introduction to Feathers text renderers
 * @see ../../../../help/bitmap-font-text-renderer.html How to use the Feathers BitmapFontTextRenderer component
 * @see http://wiki.starling-framework.org/manual/displaying_text#bitmap_fonts Starling Wiki: Displaying Text with Bitmap Fonts
 *
 * @productversion Feathers 1.0.0
 */
class BitmapFontTextRenderer extends BaseTextRenderer implements ITextRenderer {
	/**
	 * @private
	 */
	private static var HELPER_RESULT:MeasureTextResult = new MeasureTextResult();

	/**
	 * @private
	 */
	inline private static var CHARACTER_ID_SPACE:Int = 32;

	/**
	 * @private
	 */
	inline private static var CHARACTER_ID_TAB:Int = 9;

	/**
	 * @private
	 */
	inline private static var CHARACTER_ID_LINE_FEED:Int = 10;

	/**
	 * @private
	 */
	inline private static var CHARACTER_ID_CARRIAGE_RETURN:Int = 13;

	/**
	 * @private
	 */
	private static var CHARACTER_BUFFER:Array<CharLocation>;

	/**
	 * @private
	 */
	private static var CHAR_LOCATION_POOL:Array<CharLocation>;

	/**
	 * @private
	 */
	inline private static var FUZZY_MAX_WIDTH_PADDING:Float = 0.000001;

	/**
	 * The default <code>IStyleProvider</code> for all <code>BitmapFontTextRenderer</code>
	 * components.
	 *
	 * @default null
	 * @see feathers.core.FeathersControl#styleProvider
	 */
	public static var globalStyleProvider:IStyleProvider;

	/**
	 * Constructor.
	 */
	public function new() {
		super();
		if (CHAR_LOCATION_POOL == null) {
			// compiler doesn't like referencing CharLocation class in a
			// static constant
			CHAR_LOCATION_POOL = new Array();
		}
		if (CHARACTER_BUFFER == null) {
			CHARACTER_BUFFER = new Array();
		}
		this.isQuickHitAreaEnabled = true;
	}

	/**
	 * @private
	 */
	private var _characterBatch:MeshBatch = null;

	/**
	 * @private
	 * This variable may be used by subclasses to affect the x position of
	 * the text.
	 */
	private var _batchX:Float = 0;

	/**
	 * @private
	 */
	private var _textFormatChanged:Bool = true;

	/**
	 * @private
	 */
	private var _currentFontStyles:TextFormat = null;

	/**
	 * @private
	 */
	private var _fontStylesTextFormat:BitmapFontTextFormat;

	/**
	 * @private
	 */
	private var _currentVerticalAlign:String;

	/**
	 * @private
	 */
	private var _verticalAlignOffsetY:Float = 0;

	/**
	 * @private
	 */
	private var _currentTextFormat:BitmapFontTextFormat;

	/**
	 * For debugging purposes, the current
	 * <code>feathers.text.BitmapFontTextFormat</code> used to render the
	 * text. Updated during validation, and may be <code>null</code> before
	 * the first validation.
	 * 
	 * <p>Do not modify this value. It is meant for testing and debugging
	 * only. Use the parent's <code>starling.text.TextFormat</code> font
	 * styles APIs instead.</p>
	 */
	public var currentTextFormat(get, never):BitmapFontTextFormat;

	public function get_currentTextFormat():BitmapFontTextFormat {
		return this._currentTextFormat;
	}

	/**
	 * @private
	 */
	override private function get_defaultStyleProvider():IStyleProvider {
		return BitmapFontTextRenderer.globalStyleProvider;
	}

	/**
	 * @private
	 */
	override public function set_maxWidth(value:Float):Float {
		// this is a special case because truncation may bypass normal rules
		// for determining if changing maxWidth should invalidate
		var needsInvalidate:Bool = value > this._explicitMaxWidth && this._lastLayoutIsTruncated;
		super.maxWidth = value;
		if (needsInvalidate) {
			this.invalidate(FeathersControl.INVALIDATION_FLAG_SIZE);
		}

		return value;
	}

	/**
	 * @private
	 */
	private var _numLines:Int = 0;

	/**
	 * @copy feathers.core.ITextRenderer#numLines
	 */
	public var numLines(get, never):Int;

	public function get_numLines():Int {
		return this._numLines;
	}

	/**
	 * @private
	 */
	private var _textFormatForState:Map<String, BitmapFontTextFormat>;

	/**
	 * @private
	 */
	private var _textFormat:BitmapFontTextFormat;

	/**
	 * Advanced font formatting used to draw the text, if
	 * <code>fontStyles</code> and <code>starling.text.TextFormat</code>
	 * cannot be used on the parent component because the other features of
	 * bitmap fonts are required.
	 *
	 * <p>In the following example, the text format is changed:</p>
	 *
	 * <listing version="3.0">
	 * textRenderer.textFormat = new BitmapFontTextFormat( bitmapFont );</listing>
	 *
	 * <p><strong>Warning:</strong> If this property is not
	 * <code>null</code>, any <code>starling.text.TextFormat</code> font
	 * styles that are passed in from the parent component may be ignored.
	 * In other words, advanced font styling with
	 * <code>BitmapFontTextFormat</code> will always take precedence.</p>
	 *
	 * @default null
	 *
	 * @see #setTextFormatForState()
	 * @see #disabledTextFormat
	 * @see #selectedTextFormat
	 */
	public var textFormat(get, set):BitmapFontTextFormat;

	public function get_textFormat():BitmapFontTextFormat {
		return this._textFormat;
	}

	/**
	 * @private
	 */
	public function set_textFormat(value:BitmapFontTextFormat):BitmapFontTextFormat {
		if (this._textFormat == value) {
			return this._textFormat;
		}
		this._textFormat = value;
		this.invalidate(FeathersControl.INVALIDATION_FLAG_STYLES);
		return this._textFormat;
	}

	/**
	 * @private
	 */
	private var _disabledTextFormat:BitmapFontTextFormat;

	/**
	 * Advanced font formatting used to draw the text when the component is
	 * disabled, if <code>disabledFontStyles</code> and
	 * <code>starling.text.TextFormat</code> cannot be used on the parent
	 * component because the other features of bitmap fonts are required.
	 *
	 * <p>In the following example, the disabled text format is changed:</p>
	 *
	 * <listing version="3.0">
	 * textRenderer.isEnabled = false;
	 * textRenderer.disabledTextFormat = new BitmapFontTextFormat( bitmapFont );</listing>
	 *
	 * <p><strong>Warning:</strong> If this property is not
	 * <code>null</code>, any <code>starling.text.TextFormat</code> font
	 * styles that are passed in from the parent component may be ignored.
	 * In other words, advanced font styling with
	 * <code>BitmapFontTextFormat</code> will always take precedence.</p>
	 *
	 * @default null
	 * 
	 * @see #textFormat
	 * @see #selectedTextFormat
	 */
	public var disabledTextFormat(get, set):BitmapFontTextFormat;

	public function get_disabledTextFormat():BitmapFontTextFormat {
		return this._disabledTextFormat;
	}

	/**
	 * @private
	 */
	public function set_disabledTextFormat(value:BitmapFontTextFormat):BitmapFontTextFormat {
		if (this._disabledTextFormat == value) {
			return this._disabledTextFormat;
		}
		this._disabledTextFormat = value;
		this.invalidate(FeathersControl.INVALIDATION_FLAG_STYLES);
		return this._disabledTextFormat;
	}

	/**
	 * @private
	 */
	private var _selectedTextFormat:BitmapFontTextFormat;

	/**
	 * Advanced font formatting used to draw the text when the
	 * <code>stateContext</code> is disabled, if
	 * <code>selectedFontStyles</code> and
	 * <code>starling.text.TextFormat</code> cannot be used on the parent
	 * component because the other features of bitmap fonts are required.
	 *
	 * <p>In the following example, the selected text format is changed:</p>
	 *
	 * <listing version="3.0">
	 * textRenderer.selectedTextFormat = new BitmapFontTextFormat( bitmapFont );</listing>
	 *
	 * <p><strong>Warning:</strong> If this property is not
	 * <code>null</code>, any <code>starling.text.TextFormat</code> font
	 * styles that are passed in from the parent component may be ignored.
	 * In other words, advanced font styling with
	 * <code>BitmapFontTextFormat</code> will always take precedence.</p>
	 *
	 * @default null
	 *
	 * @see #stateContext
	 * @see feathers.core.IToggle
	 * @see #textFormat
	 * @see #disabledTextFormat
	 */
	public var selectedTextFormat(get, set):BitmapFontTextFormat;

	public function get_selectedTextFormat():BitmapFontTextFormat {
		return this._selectedTextFormat;
	}

	/**
	 * @private
	 */
	public function set_selectedTextFormat(value:BitmapFontTextFormat):BitmapFontTextFormat {
		if (this._selectedTextFormat == value) {
			return this._selectedTextFormat;
		}
		this._selectedTextFormat = value;
		this.invalidate(FeathersControl.INVALIDATION_FLAG_STYLES);
		return this._selectedTextFormat;
	}

	/**
	 * @private
	 */
	private var _textureSmoothing:String = null;

	// [Inspectable(type="String",enumeration="bilinear,trilinear,none")]

	/**
	 * A texture smoothing value passed to each character image. If
	 * <code>null</code>, defaults to the value specified by the
	 * <code>smoothing</code> property of the <code>BitmapFont</code>.
	 * 
	 * <p>In the following example, the texture smoothing is changed:</p>
	 *
	 * <listing version="3.0">
	 * textRenderer.textureSmoothing = TextureSmoothing.NONE;</listing>
	 *
	 * @default null
	 *
	 * @see http://doc.starling-framework.org/core/starling/textures/TextureSmoothing.html starling.textures.TextureSmoothing
	 */
	public var textureSmoothing(get, set):String;

	public function get_textureSmoothing():String {
		return this._textureSmoothing;
	}

	/**
	 * @private
	 */
	public function set_textureSmoothing(value:String):String {
		if (this._textureSmoothing == value) {
			return this._textureSmoothing;
		}
		this._textureSmoothing = value;
		this.invalidate(FeathersControl.INVALIDATION_FLAG_STYLES);
		return this._textureSmoothing;
	}

	/**
	 * @private
	 */
	private var _pixelSnapping:Bool = true;

	/**
	 * Determines if the position of the text should be snapped to the
	 * nearest whole pixel when rendered. When snapped to a whole pixel, the
	 * text is often more readable. When not snapped, the text may become
	 * blurry due to texture smoothing.
	 *
	 * <p>In the following example, the text is not snapped to pixels:</p>
	 *
	 * <listing version="3.0">
	 * textRenderer.pixelSnapping = false;</listing>
	 *
	 * @default true
	 */
	public var pixelSnapping(get, set):Bool;

	public function get_pixelSnapping():Bool {
		return _pixelSnapping;
	}

	/**
	 * @private
	 */
	public function set_pixelSnapping(value:Bool):Bool {
		if (this._pixelSnapping == value) {
			return this._pixelSnapping;
		}
		this._pixelSnapping = value;
		this.invalidate(FeathersControl.INVALIDATION_FLAG_STYLES);
		return this._pixelSnapping;
	}

	/**
	 * @private
	 */
	private var _breakLongWords:Bool = false;

	/**
	 * If <code>wordWrap</code> is <code>true</code>, determines if words
	 * longer than the width of the text renderer will break in the middle
	 * or if the word will extend outside the edges until it ends.
	 *
	 * <p>In the following example, the text will break long words:</p>
	 *
	 * <listing version="3.0">
	 * textRenderer.breakLongWords = true;</listing>
	 *
	 * @default false
	 * 
	 * @see #wordWrap
	 */
	public var breakLongWords(get, set):Bool;

	private function get_breakLongWords():Bool {
		return _breakLongWords;
	}

	/**
	 * @private
	 */
	public function set_breakLongWords(value:Bool):Bool {
		if (this._breakLongWords == value) {
			return this._breakLongWords;
		}
		this._breakLongWords = value;
		this.invalidate(FeathersControl.INVALIDATION_FLAG_STYLES);
		return this._breakLongWords;
	}

	/**
	 * @private
	 */
	private var _truncateToFit:Bool = true;

	/**
	 * If word wrap is disabled, and the text is longer than the width of
	 * the label, the text may be truncated using <code>truncationText</code>.
	 *
	 * <p>This feature may be disabled to improve performance.</p>
	 *
	 * <p>This feature does not currently support the truncation of text
	 * displayed on multiple lines.</p>
	 *
	 * <p>In the following example, truncation is disabled:</p>
	 *
	 * <listing version="3.0">
	 * textRenderer.truncateToFit = false;</listing>
	 *
	 * @default true
	 *
	 * @see #truncationText
	 */
	public var truncateToFit(get, set):Bool;

	public function get_truncateToFit():Bool {
		return _truncateToFit;
	}

	/**
	 * @private
	 */
	public function set_truncateToFit(value:Bool):Bool {
		if (this._truncateToFit == value) {
			return this._truncateToFit;
		}
		this._truncateToFit = value;
		this.invalidate(FeathersControl.INVALIDATION_FLAG_DATA);
		return this._truncateToFit;
	}

	/**
	 * @private
	 */
	private var _truncationText:String = "...";

	/**
	 * The text to display at the end of the label if it is truncated.
	 *
	 * <p>In the following example, the truncation text is changed:</p>
	 *
	 * <listing version="3.0">
	 * textRenderer.truncationText = " [more]";</listing>
	 *
	 * @default "..."
	 */
	public var truncationText(get, set):String;

	public function get_truncationText():String {
		return _truncationText;
	}

	/**
	 * @private
	 */
	public function set_truncationText(value:String):String {
		if (this._truncationText == value) {
			return this._truncationText;
		}
		this._truncationText = value;
		this.invalidate(FeathersControl.INVALIDATION_FLAG_DATA);
		return this._truncationText;
	}

	/**
	 * @private
	 */
	private var _useSeparateBatch:Bool = true;

	/**
	 * Determines if the characters are batched normally by Starling or if
	 * they're batched separately. Batching separately may improve
	 * performance for text that changes often, while batching normally
	 * may be better when a lot of text is displayed on screen at once.
	 *
	 * <p>In the following example, separate batching is disabled:</p>
	 *
	 * <listing version="3.0">
	 * textRenderer.useSeparateBatch = false;</listing>
	 *
	 * @default true
	 */
	public var useSeparateBatch(get, set):Bool;

	public function get_useSeparateBatch():Bool {
		return this._useSeparateBatch;
	}

	/**
	 * @private
	 */
	public function set_useSeparateBatch(value:Bool):Bool {
		if (this._useSeparateBatch == value) {
			return this._useSeparateBatch;
		}
		this._useSeparateBatch = value;
		this.invalidate(FeathersControl.INVALIDATION_FLAG_STYLES);
		return this._useSeparateBatch;
	}

	/**
	 * @private
	 */
	private var _defaultStyle:MeshStyle = null;

	/**
	 * @private
	 */
	private var _style:MeshStyle = null;

	/**
	 * The style that is used to render the text's mesh.
	 *
	 * <p>In the following example, the text renderer uses a custom style:</p>
	 *
	 * <listing version="3.0">
	 * textRenderer.style = new DistanceFieldStyle();</listing>
	 *
	 * @default null
	 */
	public var style(get, set):MeshStyle;

	public function get_style():MeshStyle {
		return this._style;
	}

	/**
	 * @private
	 */
	public function set_style(value:MeshStyle):MeshStyle {
		if (this._style == value) {
			return this._style;
		}
		this._style = value;
		this.invalidate(INVALIDATION_FLAG_STYLES);
		return this._style;
	}

	/**
	 * @inheritDoc
	 */
	public function get_baseline():Float {
		if (this._currentTextFormat == null) {
			return 0;
		}
		var font:BitmapFont = this._currentTextFormat.font;
		var formatSize:Float = this._currentTextFormat.size;
		var fontSizeScale:Float = formatSize / font.size;
		if (fontSizeScale != fontSizeScale) // isNaN
		{
			fontSizeScale = 1;
		}
		var baseline:Float = font.baseline;
		// for some reason, if we do the !== check on a local variable right
		// here, compiling with the flex 4.6 SDK will throw a VerifyError
		// for a stack overflow.
		// we could change the !== check back to isNaN() instead, but
		// isNaN() can allocate an object that needs garbage collection.
		this._compilerWorkaround = baseline;
		if (baseline != baseline) // isNaN
		{
			return font.lineHeight * fontSizeScale;
		}
		return baseline * fontSizeScale;
	}

	/**
	 * @private
	 */
	private var _image:Image = null;

	/**
	 * @private
	 * This function is here to work around a bug in the Flex 4.6 SDK
	 * compiler. For explanation, see the places where it gets called.
	 */
	private var _compilerWorkaround:Dynamic;

	/**
	 * @private
	 */
	override public function render(painter:Painter):Void {
		this._characterBatch.x = this._batchX;
		this._characterBatch.y = this._verticalAlignOffsetY;
		super.render(painter);
	}

	/**
	 * @inheritDoc
	 */
	public function measureText(result:Point = null):Point {
		return this.measureTextInternal(result, true);
	}

	/**
	 * Gets the advanced <code>BitmapFontTextFormat</code> font formatting
	 * passed in using <code>setTextFormatForState()</code> for the
	 * specified state.
	 *
	 * <p>If an <code>BitmapFontTextFormat</code> is not defined for a
	 * specific state, returns <code>null</code>.</p>
	 *
	 * @see #setTextFormatForState()
	 */
	public function getTextFormatForState(state:String):BitmapFontTextFormat {
		if (this._textFormatForState == null) {
			return null;
		}
		return cast this._textFormatForState.get(state);
	}

	/**
	 * Sets the advanced <code>BitmapFontTextFormat</code> font formatting
	 * to be used by the text renderer when the <code>currentState</code>
	 * property of the <code>stateContext</code> matches the specified state
	 * value. For advanced use cases where
	 * <code>starling.text.TextFormat</code> cannot be used on the parent
	 * component because other features of bitmap fonts are required.
	 *
	 * <p>If an <code>BitmapFontTextFormat</code> is not defined for a
	 * specific state, the value of the <code>textFormat</code> property
	 * will be used instead.</p>
	 *
	 * <p>If the <code>disabledTextFormat</code> property is not
	 * <code>null</code> and the <code>isEnabled</code> property is
	 * <code>false</code>, all other text formats will be ignored.</p>
	 *
	 * @see #stateContext
	 * @see #textFormat
	 */
	public function setTextFormatForState(state:String, textFormat:BitmapFontTextFormat):Void {
		if (textFormat != null) {
			if (this._textFormatForState == null) {
				this._textFormatForState = new Map<String, BitmapFontTextFormat>();
			}
			this._textFormatForState.set(state, textFormat);
		} else {
			this._textFormatForState.remove(state);
		}
		// if the context's current state is the state that we're modifying,
		// we need to use the new value immediately.
		if (this._stateContext != null && this._stateContext.currentState == state) {
			this.invalidate(INVALIDATION_FLAG_STATE);
		}
	}

	/**
	 * @private
	 */
	override private function initialize():Void {
		if (this._characterBatch == null) {
			this._characterBatch = new MeshBatch();
			this._characterBatch.touchable = false;
			this.addChild(this._characterBatch);
		}
	}

	/**
	 * @private
	 */
	private var _lastLayoutWidth:Float = 0;

	/**
	 * @private
	 */
	private var _lastLayoutHeight:Float = 0;

	/**
	 * @private
	 */
	private var _lastLayoutIsTruncated:Bool = false;

	/**
	 * @private
	 */
	override private function draw():Void {
		var dataInvalid:Bool = this.isInvalid(INVALIDATION_FLAG_DATA);
		var stylesInvalid:Bool = this.isInvalid(INVALIDATION_FLAG_STYLES);
		var stateInvalid:Bool = this.isInvalid(INVALIDATION_FLAG_STATE);

		if (stylesInvalid || stateInvalid) {
			this.refreshTextFormat();
		}

		if (stylesInvalid) {
			this._characterBatch.pixelSnapping = this._pixelSnapping;
			this._characterBatch.batchable = !this._useSeparateBatch;
		}

		// sometimes, we can determine that the layout will be exactly
		// the same without needing to update. this will result in much
		// better performance.
		var newWidth:Float = this._explicitWidth;
		if (newWidth != newWidth) // isNaN
		{
			newWidth = this._explicitMaxWidth;
		}

		// sometimes, we can determine that the dimensions will be exactly
		// the same without needing to refresh the text lines. this will
		// result in much better performance.
		var sizeInvalid:Bool;
		if (this._wordWrap) {
			// when word wrapped, we need to measure again any time that the
			// width changes.
			sizeInvalid = newWidth != this._lastLayoutWidth;
		} else {
			// we can skip measuring again more frequently when the text is
			// a single line.

			// if the width is smaller than the last layout width, we need to
			// measure again. when it's larger, the result won't change...
			sizeInvalid = newWidth < this._lastLayoutWidth;

			// ...unless the text was previously truncated!
			// sizeInvalid ||= (this._lastLayoutIsTruncated && newWidth != this._lastLayoutWidth);
			if (sizeInvalid == null) {
				sizeInvalid = (this._lastLayoutIsTruncated && newWidth != this._lastLayoutWidth);
			}

			// ... or the text is aligned
			// sizeInvalid ||= this._currentTextFormat.align != TextFormatAlign.LEFT;
			if (sizeInvalid == null) {
				sizeInvalid = this._currentTextFormat.align != TextFormatAlign.LEFT;
			}
		}

		if (dataInvalid || sizeInvalid || stylesInvalid || this._textFormatChanged) {
			this._textFormatChanged = false;
			this._characterBatch.clear();
			if (this._currentTextFormat == null || this._text == null) {
				this.saveMeasurements(0, 0, 0, 0);
				return;
			}
			this.layoutCharacters(HELPER_RESULT);
			// for some reason, we can't just set the style once...
			// we need to set up every time after layout
			if (this._style != null) {
				this._characterBatch.style = this._style;
			} else {
				// getDefaultMeshStyle doesn't exist in Starling 2.2
				this._defaultStyle = this._currentTextFormat.font.getDefaultMeshStyle(this._defaultStyle, this._currentFontStyles, null);
				if (this._defaultStyle != null) {
					this._characterBatch.style = this._defaultStyle;
				}
			}
			this._lastLayoutWidth = HELPER_RESULT.width;
			this._lastLayoutHeight = HELPER_RESULT.height;
			this._lastLayoutIsTruncated = HELPER_RESULT.isTruncated;
		}
		this.saveMeasurements(this._lastLayoutWidth, this._lastLayoutHeight, this._lastLayoutWidth, this._lastLayoutHeight);
		this._verticalAlignOffsetY = this.getVerticalAlignOffsetY();
	}

	/**
	 * @private
	 */
	private function layoutCharacters(result:MeasureTextResult = null):MeasureTextResult {
		if (result == null) {
			result = new MeasureTextResult();
		}
		this._numLines = 1;

		var font:BitmapFont = this._currentTextFormat.font;
		var customSize:Float = this._currentTextFormat.size;
		var customLetterSpacing:Float = this._currentTextFormat.letterSpacing;
		var isKerningEnabled:Bool = this._currentTextFormat.isKerningEnabled;
		var scale:Float = customSize / font.size;
		if (scale != scale) // isNaN
		{
			scale = 1;
		}
		var lineHeight:Float = font.lineHeight * scale + this._currentTextFormat.leading;
		var offsetX:Float = font.offsetX * scale;
		var offsetY:Float = font.offsetY * scale;

		var hasExplicitWidth:Bool = this._explicitWidth == this._explicitWidth; // !isNaN
		var isAligned:Bool = this._currentTextFormat.align != TextFormatAlign.LEFT;
		var maxLineWidth:Float = hasExplicitWidth ? this._explicitWidth : this._explicitMaxWidth;
		if (isAligned && maxLineWidth == Math.POSITIVE_INFINITY) {
			// we need to measure the text to get the maximum line width
			// so that we can align the text
			var point:Point = Pool.getPoint();
			this.measureText(point);
			maxLineWidth = point.x;
			Pool.putPoint(point);
		}
		var textToDraw:String = this._text;
		if (this._truncateToFit) {
			var truncatedText:String = this.getTruncatedText(maxLineWidth);
			result.isTruncated = truncatedText != textToDraw;
			textToDraw = truncatedText;
		} else {
			result.isTruncated = false;
		}
		CHARACTER_BUFFER = [];

		var maxX:Float = 0;
		var currentX:Float = 0;
		var currentY:Float = 0;
		var previousCharID:Float = Math.NaN;
		var isWordComplete:Bool = false;
		var startXOfPreviousWord:Float = 0;
		var widthOfWhitespaceAfterWord:Float = 0;
		var wordLength:Int = 0;
		var wordCountForLine:Int = 0;
		var charData:BitmapChar = null;
		var charCount:Int = textToDraw != null ? textToDraw.length : 0;
		// for (var i:Int = 0; i < charCount; i++)
		for (i in 0...charCount) {
			isWordComplete = false;
			var charID:Int = textToDraw.charCodeAt(i);
			if (charID == CHARACTER_ID_LINE_FEED || charID == CHARACTER_ID_CARRIAGE_RETURN) // new line \n or \r
			{
				// remove whitespace after the final character in the line
				currentX -= customLetterSpacing;
				if (charData != null) {
					currentX -= (charData.xAdvance - charData.width) * scale;
				}
				if (currentX < 0) {
					currentX = 0;
				}
				if (this._wordWrap || isAligned) {
					this.alignBuffer(maxLineWidth, currentX, 0);
					this.addBufferToBatch(0);
				}
				if (maxX < currentX) {
					maxX = currentX;
				}
				previousCharID = Math.NaN;
				currentX = 0;
				currentY += lineHeight;
				startXOfPreviousWord = 0;
				widthOfWhitespaceAfterWord = 0;
				wordLength = 0;
				wordCountForLine = 0;
				this._numLines++;
				continue;
			}

			charData = font.getChar(charID);
			if (charData == null) {
				trace("Missing character " + String.fromCharCode(charID) + " in font " + font.name + ".");
				continue;
			}

			if (isKerningEnabled && previousCharID == previousCharID) // !isNaN
			{
				currentX += charData.getKerning(Std.int(previousCharID)) * scale;
			}

			var xAdvance:Float = charData.xAdvance * scale;
			var previousCharData:BitmapChar;
			if (this._wordWrap) {
				var currentCharIsWhitespace:Bool = charID == CHARACTER_ID_SPACE || charID == CHARACTER_ID_TAB;
				var previousCharIsWhitespace:Bool = previousCharID == CHARACTER_ID_SPACE || previousCharID == CHARACTER_ID_TAB;
				if (currentCharIsWhitespace) {
					if (!previousCharIsWhitespace) {
						// this is the spacing after the last character
						// that isn't whitespace
						previousCharData = font.getChar(Std.int(previousCharID));
						widthOfWhitespaceAfterWord = customLetterSpacing + (previousCharData.xAdvance - previousCharData.width) * scale;
					}
					widthOfWhitespaceAfterWord += xAdvance;
				} else if (previousCharIsWhitespace) {
					startXOfPreviousWord = currentX;
					wordLength = 0;
					wordCountForLine++;
					isWordComplete = true;
				}

				// we may need to move to a new line at the same time
				// that our previous word in the buffer can be batched
				// so we need to add the buffer here rather than after
				// the next section
				if (isWordComplete && !isAligned) {
					this.addBufferToBatch(0);
				}

				// floating point errors can cause unnecessary line breaks,
				// so we're going to be a little bit fuzzy on the greater
				// than check. such tiny numbers shouldn't break anything.
				var charWidth:Float = charData.width * scale;
				if (!currentCharIsWhitespace
					&& (wordCountForLine > 0 || this._breakLongWords)
					&& ((currentX + charWidth) - maxLineWidth) > FUZZY_MAX_WIDTH_PADDING) {
					if (wordCountForLine == 0) {
						// if we're breaking long words, this is where we break.
						// we need to pretend that there's a word before this one.
						wordLength = 0;
						startXOfPreviousWord = currentX;
						widthOfWhitespaceAfterWord = 0;
						if (previousCharID == previousCharID) // !isNaN
						{
							previousCharData = font.getChar(Std.int(previousCharID));
							widthOfWhitespaceAfterWord = customLetterSpacing + (previousCharData.xAdvance - previousCharData.width) * scale;
						}
						if (!isAligned) {
							this.addBufferToBatch(0);
						}
					}
					if (isAligned) {
						this.trimBuffer(wordLength);
						this.alignBuffer(maxLineWidth, startXOfPreviousWord - widthOfWhitespaceAfterWord, wordLength);
						this.addBufferToBatch(wordLength);
					}
					this.moveBufferedCharacters(-startXOfPreviousWord, lineHeight, 0);
					// we're just reusing this variable to avoid creating a
					// new one. it'll be reset to 0 in a moment.
					widthOfWhitespaceAfterWord = startXOfPreviousWord - widthOfWhitespaceAfterWord;
					if (maxX < widthOfWhitespaceAfterWord) {
						maxX = widthOfWhitespaceAfterWord;
					}
					previousCharID = Math.NaN;
					currentX -= startXOfPreviousWord;
					currentY += lineHeight;
					startXOfPreviousWord = 0;
					widthOfWhitespaceAfterWord = 0;
					wordLength = 0;
					isWordComplete = false;
					wordCountForLine = 0;
					this._numLines++;
				}
			}
			if (this._wordWrap || isAligned) {
				var charLocation:CharLocation = CHAR_LOCATION_POOL.length > 0 ? CHAR_LOCATION_POOL.shift() : new CharLocation();
				charLocation.char = charData;
				charLocation.x = currentX + offsetX + charData.xOffset * scale;
				charLocation.y = currentY + offsetY + charData.yOffset * scale;
				charLocation.scale = scale;
				CHARACTER_BUFFER[CHARACTER_BUFFER.length] = charLocation;
				wordLength++;
			} else {
				this.addCharacterToBatch(charData, currentX + offsetX + charData.xOffset * scale, currentY + offsetY + charData.yOffset * scale, scale);
			}

			currentX += xAdvance + customLetterSpacing;
			previousCharID = charID;
		}
		// remove whitespace after the final character in the final line
		currentX = currentX - customLetterSpacing;
		if (charData != null) {
			currentX -= (charData.xAdvance - charData.width) * scale;
		}
		if (currentX < 0) {
			currentX = 0;
		}
		if (this._wordWrap || isAligned) {
			this.alignBuffer(maxLineWidth, currentX, 0);
			this.addBufferToBatch(0);
		}
		// if the text ends in extra whitespace, the currentX value will be
		// larger than the max line width. we'll remove that and add extra
		// lines.
		if (this._wordWrap) {
			while (currentX > maxLineWidth && !MathUtil.isEquivalent(currentX, maxLineWidth)) {
				currentX -= maxLineWidth;
				currentY += lineHeight;
				if (maxLineWidth == 0) {
					// we don't want to get stuck in an infinite loop!
					break;
				}
			}
		}
		if (maxX < currentX) {
			maxX = currentX;
		}

		if (isAligned && !hasExplicitWidth) {
			var align:String = this._currentTextFormat.align;
			if (align == TextFormatAlign.CENTER) {
				this._batchX = (maxX - maxLineWidth) / 2;
			} else if (align == TextFormatAlign.RIGHT) {
				this._batchX = maxX - maxLineWidth;
			}
		} else {
			this._batchX = 0;
		}
		this._characterBatch.x = this._batchX;

		result.width = maxX;
		result.height = currentY + lineHeight - this._currentTextFormat.leading;
		return result;
	}

	/**
	 * @private
	 */
	private function trimBuffer(skipCount:Int):Void {
		var countToRemove:Int = 0;
		var charCount:Int = CHARACTER_BUFFER.length - skipCount;
		// for (var i:Int = charCount - 1; i >= 0; i--)
		for (i in(0...charCount).reverse()) {
			var charLocation:CharLocation = CHARACTER_BUFFER[i];
			var charData:BitmapChar = charLocation.char;
			var charID:int = charData.charID;
			if (charID == CHARACTER_ID_SPACE || charID == CHARACTER_ID_TAB) {
				countToRemove++;
			} else {
				break;
			}
		}
		if (countToRemove > 0) {
			CHARACTER_BUFFER.splice(i + 1, countToRemove);
		}
	}
}

class CharLocation {
	public function new() {}

	public var char:BitmapChar;
	public var scale:Float;
	public var x:Float;
	public var y:Float;
}