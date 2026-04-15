# Pattern Scheduler Browser Tests

## 1. Scheduler Initialization
**Seed:** `playwright-tests/seed.spec.ts`

### 1.1 Scheduler starts and produces audio
**Steps:**
1. Click the "Scheduler" button
2. Wait for the status to show "Audio running via Pattern Scheduler (Phase 5)"
3. Wait 500ms for audio to process
4. Verify the render peak value is greater than 0 (signal is flowing)

**Expected:** Audio context is created, scheduler mode is active, and audio samples are non-silent.

### 1.2 Default pattern auto-evaluates
**Steps:**
1. Click the "Scheduler" button
2. Wait for status to show audio running
3. Wait 500ms for the auto-eval timeout (200ms) plus audio processing
4. Check that the pattern status shows "Pattern updated"

**Expected:** The default pattern `s("bd sd hh sd").fast(2)` is automatically evaluated on startup.

## 2. Pattern Text Input
**Seed:** `playwright-tests/seed.spec.ts`

### 2.1 Eval a drum pattern via text input
**Steps:**
1. Click the "Scheduler" button
2. Wait for audio running status
3. Clear the pattern input field
4. Type `s("bd sd hh sd")` into the pattern input
5. Click the "Eval" button
6. Verify the pattern status shows "Pattern updated"
7. Wait 300ms for audio to process
8. Verify render peak is greater than 0

**Expected:** Pattern is parsed and audio plays with non-zero signal.

### 2.2 Eval a note pattern
**Steps:**
1. Click the "Scheduler" button
2. Wait for audio running status
3. Clear the pattern input field
4. Type `note("60 64 67")` into the pattern input
5. Press Enter key
6. Verify pattern status shows "Pattern updated"
7. Wait 300ms
8. Verify render peak is greater than 0

**Expected:** Note patterns work, Enter key triggers eval.

### 2.3 Parse error shows message
**Steps:**
1. Click the "Scheduler" button
2. Wait for audio running status
3. Clear the pattern input field
4. Type `invalid!!!` into the pattern input
5. Click the "Eval" button
6. Verify the pattern status text contains an error message (not "Pattern updated")
7. Verify the pattern status color is the error color

**Expected:** Invalid patterns show parse error, previous pattern continues playing.

### 2.4 Unknown drum name shows error
**Steps:**
1. Click the "Scheduler" button
2. Wait for audio running status
3. Clear the pattern input field
4. Type `s("snare")` into the pattern input
5. Click the "Eval" button
6. Verify the pattern status contains error text

**Expected:** Unknown sound names are rejected with a descriptive error.

## 3. BPM and Gain Controls
**Seed:** `playwright-tests/seed.spec.ts`

### 3.1 BPM slider updates display
**Steps:**
1. Click the "Scheduler" button
2. Wait for audio running status
3. Set the BPM slider to 180
4. Verify the BPM display shows "180"

**Expected:** BPM slider controls tempo and updates the display label.

### 3.2 Gain slider controls volume
**Steps:**
1. Click the "Scheduler" button
2. Wait for audio running status
3. Wait 300ms for audio
4. Record the current render peak
5. Set the gain slider to 0
6. Wait 300ms
7. Verify render peak is now 0 or very close to 0

**Expected:** Setting gain to 0 silences the output.

## 4. Stop and Restart
**Seed:** `playwright-tests/seed.spec.ts`

### 4.1 Stop button silences audio
**Steps:**
1. Click the "Scheduler" button
2. Wait for audio running status
3. Wait 300ms
4. Click the "Stop" button
5. Verify the status shows "Stopped."

**Expected:** Stop button cleanly shuts down audio.
