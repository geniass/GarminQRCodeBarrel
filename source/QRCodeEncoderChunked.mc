import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

module QRCode {

// Callback type for when encoding completes
typedef QREncodeCallback as Method(encoder as Encoder?) as Void;

// Chunked QR Code encoder that splits work across timer callbacks
// to avoid watchdog timeout on slow devices
class EncoderChunked {

    // Encoding states
    private enum {
        STATE_IDLE,
        STATE_INIT_MATRIX,
        STATE_FINDER_PATTERNS,
        STATE_ALIGNMENT,
        STATE_TIMING,
        STATE_FUNCTION_MASK,
        STATE_BUILD_DATA,
        STATE_ERROR_CORRECTION,
        STATE_PLACE_DATA,
        STATE_APPLY_MASK,
        STATE_FORMAT_INFO,
        STATE_COMPLETE,
        STATE_ERROR
    }

    // Current state
    private var mState as Number;

    // The actual encoder being built
    private var mEncoder as Encoder?;

    // Input data
    private var mData as String;
    private var mVersion as Number;
    private var mErrorLevel as Number;

    // Callback when complete
    private var mCallback as QREncodeCallback?;

    // Timer for chunked processing
    private var mTimer as Timer.Timer?;

    // Intermediate data between states
    private var mBits as Array<Boolean>?;

    // Timer interval in ms (short enough to be responsive, long enough to do work)
    private const TIMER_INTERVAL = 50;

    // Constructor
    function initialize() {
        mState = STATE_IDLE;
        mEncoder = null;
        mData = "";
        mVersion = 2;
        mErrorLevel = Encoder.ERROR_LEVEL_L;
        mCallback = null;
        mTimer = null;
        mBits = null;
    }

    // Start encoding asynchronously
    // @param data The string to encode
    // @param version QR code version (1-3)
    // @param errorLevel Error correction level
    // @param callback Called when encoding completes (with encoder or null on error)
    function startEncode(data as String, version as Number, errorLevel as Number, callback as QREncodeCallback) as Void {
        System.println("QR Chunked: startEncode() - " + data);

        // Cancel any existing encoding
        stopEncode();

        mData = data.toUpper();
        mVersion = version;
        mErrorLevel = errorLevel;
        mCallback = callback;

        // Validate input
        if (!isAlphanumeric(mData)) {
            System.println("QR Chunked: not alphanumeric, failing");
            mState = STATE_ERROR;
            invokeCallback(null);
            return;
        }

        // Create the encoder
        mEncoder = new Encoder(mVersion, mErrorLevel);
        mState = STATE_INIT_MATRIX;

        // Start timer for chunked processing
        mTimer = new Timer.Timer();
        mTimer.start(method(:onTimerTick), TIMER_INTERVAL, true);

        System.println("QR Chunked: timer started");
    }

    // Stop encoding (cancel if in progress)
    function stopEncode() as Void {
        if (mTimer != null) {
            mTimer.stop();
            mTimer = null;
        }
        mState = STATE_IDLE;
        mEncoder = null;
        mBits = null;
    }

    // Check if encoding is in progress
    function isEncoding() as Boolean {
        return mState != STATE_IDLE && mState != STATE_COMPLETE && mState != STATE_ERROR;
    }

    // Check if encoding is complete
    function isComplete() as Boolean {
        return mState == STATE_COMPLETE;
    }

    // Get the encoder (only valid after STATE_COMPLETE)
    function getEncoder() as Encoder? {
        return mEncoder;
    }

    // Timer callback - process next chunk of work
    function onTimerTick() as Void {
        System.println("QR Chunked: tick - state=" + mState);

        switch (mState) {
            case STATE_INIT_MATRIX:
                doInitMatrix();
                break;
            case STATE_FINDER_PATTERNS:
                doFinderPatterns();
                break;
            case STATE_ALIGNMENT:
                doAlignment();
                break;
            case STATE_TIMING:
                doTiming();
                break;
            case STATE_FUNCTION_MASK:
                doFunctionMask();
                break;
            case STATE_BUILD_DATA:
                doBuildData();
                break;
            case STATE_ERROR_CORRECTION:
                doErrorCorrection();
                break;
            case STATE_PLACE_DATA:
                doPlaceData();
                break;
            case STATE_APPLY_MASK:
                doApplyMask();
                break;
            case STATE_FORMAT_INFO:
                doFormatInfo();
                break;
            case STATE_COMPLETE:
            case STATE_ERROR:
                // Stop timer and invoke callback
                if (mTimer != null) {
                    mTimer.stop();
                    mTimer = null;
                }
                invokeCallback(mState == STATE_COMPLETE ? mEncoder : null);
                mState = STATE_IDLE;
                break;
        }
    }

    // State handlers - each does a small chunk of work

    private function doInitMatrix() as Void {
        System.println("QR Chunked: init matrix complete");
        // Matrix is initialized in constructor, move to next state
        mState = STATE_FINDER_PATTERNS;
    }

    private function doFinderPatterns() as Void {
        System.println("QR Chunked: adding finder patterns");
        if (mEncoder != null) {
            // Use internal method via encode step
            addFinderPatternsToEncoder();
        }
        mState = STATE_ALIGNMENT;
    }

    private function doAlignment() as Void {
        System.println("QR Chunked: adding alignment");
        if (mEncoder != null) {
            addAlignmentPatternToEncoder();
        }
        mState = STATE_TIMING;
    }

    private function doTiming() as Void {
        System.println("QR Chunked: adding timing");
        if (mEncoder != null) {
            addTimingPatternsToEncoder();
            addDarkModuleToEncoder();
        }
        mState = STATE_FUNCTION_MASK;
    }

    private function doFunctionMask() as Void {
        System.println("QR Chunked: building function mask");
        if (mEncoder != null) {
            buildFunctionMaskForEncoder();
        }
        mState = STATE_BUILD_DATA;
    }

    private function doBuildData() as Void {
        System.println("QR Chunked: building data bits");
        if (mEncoder != null) {
            mBits = buildDataBitsForEncoder();
            System.println("QR Chunked: data bits = " + mBits.size());
        }
        mState = STATE_ERROR_CORRECTION;
    }

    private function doErrorCorrection() as Void {
        System.println("QR Chunked: adding error correction");
        if (mEncoder != null && mBits != null) {
            mBits = addErrorCorrectionForEncoder(mBits);
            System.println("QR Chunked: with ECC = " + mBits.size());
        }
        mState = STATE_PLACE_DATA;
    }

    private function doPlaceData() as Void {
        System.println("QR Chunked: placing data");
        if (mEncoder != null && mBits != null) {
            placeDataBitsInEncoder(mBits);
        }
        mState = STATE_APPLY_MASK;
    }

    private function doApplyMask() as Void {
        System.println("QR Chunked: applying mask");
        if (mEncoder != null) {
            applyMaskToEncoder();
        }
        mState = STATE_FORMAT_INFO;
    }

    private function doFormatInfo() as Void {
        System.println("QR Chunked: adding format info");
        if (mEncoder != null) {
            addFormatInfoToEncoder();
        }
        System.println("QR Chunked: COMPLETE");
        mState = STATE_COMPLETE;
    }

    private function invokeCallback(encoder as Encoder?) as Void {
        if (mCallback != null) {
            mCallback.invoke(encoder);
        }
        // Request UI update
        WatchUi.requestUpdate();
    }

    // Check if string contains only alphanumeric characters
    private function isAlphanumeric(data as String) as Boolean {
        var chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";
        for (var i = 0; i < data.length(); i++) {
            var c = data.substring(i, i + 1);
            if (chars.find(c) == null) {
                return false;
            }
        }
        return true;
    }

    // --- Encoder manipulation functions ---
    // These directly manipulate the encoder's matrix since we can't call private methods

    private function getMatrix() as Array<Array<Boolean> > {
        return mEncoder.getMatrix();
    }

    private function getSize() as Number {
        return mEncoder.getSize();
    }

    private function addFinderPatternsToEncoder() as Void {
        var matrix = getMatrix();
        var size = getSize();
        var positions = [[0, 0], [size - 7, 0], [0, size - 7]];

        for (var p = 0; p < positions.size(); p++) {
            var row = positions[p][0];
            var col = positions[p][1];

            for (var i = 0; i < 7; i++) {
                for (var j = 0; j < 7; j++) {
                    if (i == 0 || i == 6 || j == 0 || j == 6 ||
                        (i >= 2 && i <= 4 && j >= 2 && j <= 4)) {
                        matrix[row + i][col + j] = true;
                    } else {
                        matrix[row + i][col + j] = false;
                    }
                }
            }

            // White separator
            for (var i = 0; i < 8; i++) {
                if (row - 1 >= 0 && col + i < size) { matrix[row - 1][col + i] = false; }
                if (row + 7 < size && col + i < size) { matrix[row + 7][col + i] = false; }
                if (col - 1 >= 0 && row + i < size) { matrix[row + i][col - 1] = false; }
                if (col + 7 < size && row + i < size) { matrix[row + i][col + 7] = false; }
            }
        }
    }

    private function addAlignmentPatternToEncoder() as Void {
        if (mVersion < 2) {
            return;
        }

        var center = 0;
        if (mVersion == 2) { center = 18; }
        else if (mVersion == 3) { center = 22; }

        if (center == 0) {
            return;
        }

        var matrix = getMatrix();

        for (var dr = -2; dr <= 2; dr++) {
            for (var dc = -2; dc <= 2; dc++) {
                var r = center + dr;
                var c = center + dc;
                if (dr == -2 || dr == 2 || dc == -2 || dc == 2 || (dr == 0 && dc == 0)) {
                    matrix[r][c] = true;
                } else {
                    matrix[r][c] = false;
                }
            }
        }
    }

    private function addTimingPatternsToEncoder() as Void {
        var matrix = getMatrix();
        var size = getSize();

        for (var i = 8; i < size - 8; i++) {
            matrix[6][i] = (i % 2 == 0);
            matrix[i][6] = (i % 2 == 0);
        }
    }

    private function addDarkModuleToEncoder() as Void {
        var matrix = getMatrix();
        matrix[4 * mVersion + 9][8] = true;
    }

    // Store function mask separately since encoder's is private
    private var mFunctionMask as Array<Array<Boolean> >?;

    private function buildFunctionMaskForEncoder() as Void {
        var size = getSize();
        mFunctionMask = new Array<Array<Boolean> >[size];
        for (var i = 0; i < size; i++) {
            mFunctionMask[i] = new Array<Boolean>[size];
            for (var j = 0; j < size; j++) {
                mFunctionMask[i][j] = isFunctionModule(i, j);
            }
        }
    }

    private function isFunctionModule(row as Number, col as Number) as Boolean {
        var size = getSize();

        // Finder patterns (3 corners) with separators
        if (row < 9 && col < 9) { return true; }
        if (row < 9 && col >= size - 8) { return true; }
        if (row >= size - 8 && col < 9) { return true; }

        // Timing patterns
        if (row == 6 || col == 6) { return true; }

        // Alignment pattern (for version 2+)
        if (mVersion >= 2) {
            var alignCenter = 0;
            if (mVersion == 2) { alignCenter = 18; }
            else if (mVersion == 3) { alignCenter = 22; }

            if (alignCenter > 0) {
                var dr = row - alignCenter;
                var dc = col - alignCenter;
                if (dr >= -2 && dr <= 2 && dc >= -2 && dc <= 2) {
                    return true;
                }
            }
        }

        return false;
    }

    // Alphanumeric character set
    private const ALPHANUMERIC_CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";

    private function getAlphanumericValue(c as String) as Number {
        var index = ALPHANUMERIC_CHARS.find(c);
        if (index != null) {
            return index;
        }
        return 0;
    }

    private function getDataCapacity() as Number {
        var capacities = [
            [152, 272, 440],
            [128, 224, 352],
            [104, 176, 272],
            [72, 128, 208]
        ];
        return capacities[mErrorLevel][mVersion - 1];
    }

    private function getCountBits() as Number {
        if (mVersion <= 9) {
            return 9;
        } else if (mVersion <= 26) {
            return 11;
        } else {
            return 13;
        }
    }

    private function buildDataBitsForEncoder() as Array<Boolean> {
        var capacity = getDataCapacity();
        var bits = new Array<Boolean>[capacity];
        var bitIndex = 0;

        // Mode indicator (0010 = alphanumeric)
        bitIndex = addBitsAt(bits, bitIndex, 2, 4);

        // Character count
        var countBits = getCountBits();
        bitIndex = addBitsAt(bits, bitIndex, mData.length(), countBits);

        // Encode data in pairs
        for (var i = 0; i < mData.length(); i += 2) {
            if (i + 1 < mData.length()) {
                var val1 = getAlphanumericValue(mData.substring(i, i + 1));
                var val2 = getAlphanumericValue(mData.substring(i + 1, i + 2));
                bitIndex = addBitsAt(bits, bitIndex, val1 * 45 + val2, 11);
            } else {
                var val = getAlphanumericValue(mData.substring(i, i + 1));
                bitIndex = addBitsAt(bits, bitIndex, val, 6);
            }
        }

        // Terminator
        var remaining = capacity - bitIndex;
        if (remaining > 4) {
            remaining = 4;
        }
        for (var i = 0; i < remaining; i++) {
            bits[bitIndex] = false;
            bitIndex++;
        }

        // Pad to byte boundary
        while (bitIndex % 8 != 0) {
            bits[bitIndex] = false;
            bitIndex++;
        }

        // Add padding bytes
        var padBytes = [236, 17];
        var padIdx = 0;
        while (bitIndex < capacity) {
            bitIndex = addBitsAt(bits, bitIndex, padBytes[padIdx], 8);
            padIdx = (padIdx + 1) % 2;
        }

        return bits;
    }

    private function addBitsAt(bits as Array<Boolean>, index as Number, value as Number, length as Number) as Number {
        for (var i = length - 1; i >= 0; i--) {
            bits[index] = (value & (1 << i)) != 0;
            index++;
        }
        return index;
    }

    private function getECCCount() as Number {
        var eccTable = [
            [7, 10, 13],
            [10, 16, 22],
            [13, 22, 28],
            [17, 28, 36]
        ];
        return eccTable[mErrorLevel][mVersion - 1];
    }

    // Cached generator polynomial
    private static var sCachedGenerator as Array<Number>?;
    private static var sCachedGeneratorECC as Number = 0;

    private function generateGeneratorPolynomial(numECC as Number) as Array<Number> {
        if (sCachedGenerator != null && sCachedGeneratorECC == numECC) {
            return sCachedGenerator;
        }

        var gen = [1] as Array<Number>;

        for (var i = 0; i < numECC; i++) {
            var term = [1, GaloisField.GF_EXP[i]] as Array<Number>;
            gen = polyMultiply(gen, term);
        }

        sCachedGenerator = gen;
        sCachedGeneratorECC = numECC;

        return gen;
    }

    private function polyMultiply(p1 as Array<Number>, p2 as Array<Number>) as Array<Number> {
        var result = new Array<Number>[p1.size() + p2.size() - 1];
        for (var i = 0; i < result.size(); i++) {
            result[i] = 0;
        }

        for (var i = 0; i < p1.size(); i++) {
            for (var j = 0; j < p2.size(); j++) {
                result[i + j] = result[i + j] ^ GaloisField.multiply(p1[i], p2[j]);
            }
        }

        return result;
    }

    private function addErrorCorrectionForEncoder(bits as Array<Boolean>) as Array<Boolean> {
        // Convert bits to bytes
        var dataBytes = new Array<Number>[bits.size() / 8];
        for (var i = 0; i < dataBytes.size(); i++) {
            var byte = 0;
            for (var j = 0; j < 8; j++) {
                if (bits[i * 8 + j]) {
                    byte = byte | (1 << (7 - j));
                }
            }
            dataBytes[i] = byte;
        }

        var numECC = getECCCount();
        var generator = generateGeneratorPolynomial(numECC);

        // Prepare message polynomial
        var message = new Array<Number>[dataBytes.size() + numECC];
        for (var i = 0; i < dataBytes.size(); i++) {
            message[i] = dataBytes[i];
        }
        for (var i = dataBytes.size(); i < message.size(); i++) {
            message[i] = 0;
        }

        // Polynomial division
        var result = new Array<Number>[message.size()];
        for (var i = 0; i < message.size(); i++) {
            result[i] = message[i];
        }

        for (var i = 0; i < message.size() - generator.size() + 1; i++) {
            var coef = result[i];
            if (coef != 0) {
                for (var j = 1; j < generator.size(); j++) {
                    if (generator[j] != 0) {
                        result[i + j] = result[i + j] ^ GaloisField.multiply(generator[j], coef);
                    }
                }
            }
        }

        // Get remainder (ECC bytes)
        var eccBytes = new Array<Number>[generator.size() - 1];
        for (var i = 0; i < eccBytes.size(); i++) {
            eccBytes[i] = result[result.size() - eccBytes.size() + i];
        }

        // Combine data and ECC
        var allBytes = new Array<Number>[dataBytes.size() + eccBytes.size()];
        for (var i = 0; i < dataBytes.size(); i++) {
            allBytes[i] = dataBytes[i];
        }
        for (var i = 0; i < eccBytes.size(); i++) {
            allBytes[dataBytes.size() + i] = eccBytes[i];
        }

        // Convert back to bits
        var resultBits = new Array<Boolean>[allBytes.size() * 8];
        for (var i = 0; i < allBytes.size(); i++) {
            for (var j = 0; j < 8; j++) {
                resultBits[i * 8 + j] = (allBytes[i] & (1 << (7 - j))) != 0;
            }
        }

        return resultBits;
    }

    private function placeDataBitsInEncoder(bits as Array<Boolean>) as Void {
        var matrix = getMatrix();
        var size = getSize();
        var bitIndex = 0;
        var direction = -1;

        for (var col = size - 1; col >= 1; col -= 2) {
            if (col == 6) { col = 5; }

            for (var i = 0; i < size; i++) {
                var row = direction == -1 ? size - 1 - i : i;

                for (var c = 0; c < 2; c++) {
                    var x = col - c;

                    if (mFunctionMask != null && mFunctionMask[row][x]) {
                        continue;
                    }

                    if (bitIndex < bits.size()) {
                        matrix[row][x] = bits[bitIndex];
                        bitIndex++;
                    }
                }
            }
            direction = -direction;
        }
    }

    private const MASK_PATTERN = 5;

    private function applyMaskToEncoder() as Void {
        var matrix = getMatrix();
        var size = getSize();

        for (var row = 0; row < size; row++) {
            for (var col = 0; col < size; col++) {
                if (mFunctionMask != null && !mFunctionMask[row][col]) {
                    if (shouldMask(row, col)) {
                        matrix[row][col] = !matrix[row][col];
                    }
                }
            }
        }
    }

    private function shouldMask(row as Number, col as Number) as Boolean {
        // Mask pattern 5: ((row * col) % 2) + ((row * col) % 3) == 0
        return ((row * col) % 2) + ((row * col) % 3) == 0;
    }

    private function addFormatInfoToEncoder() as Void {
        var matrix = getMatrix();
        var size = getSize();

        // Generate format bits
        var eccBits = [
            [0, 1], [0, 0], [1, 1], [1, 0]
        ];

        var formatData = (eccBits[mErrorLevel][0] << 4) | (eccBits[mErrorLevel][1] << 3) | MASK_PATTERN;

        var generator = 0x537;
        var bch = formatData << 10;

        for (var i = 4; i >= 0; i--) {
            if ((bch >> (i + 10)) != 0) {
                bch = bch ^ (generator << i);
            }
        }

        var formatBits15 = (formatData << 10) | bch;
        formatBits15 = formatBits15 ^ 0x5412;

        var formatBits = new Array<Boolean>[15];
        for (var i = 0; i < 15; i++) {
            formatBits[i] = ((formatBits15 >> (14 - i)) & 1) != 0;
        }

        // Place format info
        for (var i = 0; i < 6; i++) {
            matrix[8][i] = formatBits[i];
        }
        matrix[8][7] = formatBits[6];
        matrix[8][8] = formatBits[7];

        matrix[7][8] = formatBits[8];
        matrix[5][8] = formatBits[9];
        matrix[4][8] = formatBits[10];
        matrix[3][8] = formatBits[11];
        matrix[2][8] = formatBits[12];
        matrix[1][8] = formatBits[13];
        matrix[0][8] = formatBits[14];

        for (var i = 0; i < 7; i++) {
            matrix[size - 1 - i][8] = formatBits[i];
        }

        for (var i = 0; i < 8; i++) {
            matrix[8][size - 8 + i] = formatBits[7 + i];
        }
    }
}

} // module QRCode
