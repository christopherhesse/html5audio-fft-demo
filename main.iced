# TODO:
# TODO: freq wrapping
#     first - look at freqs of spikes - see if they are integer multiples
#     where do harmonics occur? fq, 2*fq, 3*fq?  notes occur at fq, 2*fq, 4*fq
#     for each note, sum all harmonics?
# TODO: stereo (freq only uses left channel, mix together for now)

UPDATE_PERIOD = 50 # ms
SPECTROGRAM_ROWS = 20
SPECTROGRAM_ROW_HEIGHT = 5
KEY_WIDTH = 20

set_timeout = (timeout, f) ->
    setTimeout(f, timeout)

set_interval = (timeout, f) ->
    setInterval(f, timeout)

gen_notes = ->
    names = ["A", "A#/Bb", "B", "C", "C#/Db", "D", "D#/Eb", "E", "F", "F#/Gb", "G", "G#/Ab"]
    freq = 27.5000
    name_index = 0
    octave = 0

    notes = []
    while freq < 4186.1
        name = names[name_index]
        # true if the note is a white key on a piano
        white = name.indexOf("/") == -1
        note = {name: name, octave: octave, freq: freq, white: white}
        notes.push(note)

        name_index = (name_index + 1) % names.length
        freq = freq * Math.pow(2, 1/12)
        if names[name_index] == "C"
            octave += 1

    return notes

NOTES = gen_notes()

gen_freq_bins = (sampleRate, frequencyBinCount, fftSize) ->
    freqBins = [0]
    while freqBins.length < frequencyBinCount
        freqBins.push(_.last(freqBins) + sampleRate/fftSize)

    # freqBins.shift() # FFT may not include DC
    return freqBins

convert_to_note_magnitudes = (freqData, freqBins) ->
    # for each note, get magnitudes by interpolating between freqData points
    magnitudes = []
    for note in NOTES
        # find the nearest two frequencies in freqBins
        for freq, index in freqBins
            if freq > note.freq
                break

        # linear interpolation
        lowerFreq = freqBins[index - 1]
        upperFreq = freq
        lowerMagnitude = freqData[index - 1]
        upperMagnitude = freqData[index]

        slope = (upperMagnitude - lowerMagnitude) / (upperFreq - lowerFreq)
        magnitude = slope * (note.freq - lowerFreq) + lowerMagnitude
        magnitudes.push(magnitude)

    return magnitudes

create_context = (width, height) ->
    $canvas = $("<canvas></canvas>")
    $(document.body).append($canvas)
    canvas_elem = $canvas[0]

    canvas_elem.width = width
    canvas_elem.height = height

    canvas = canvas_elem.getContext("2d")
    canvas.elem = canvas_elem
    return canvas

clear_canvas = (canvas) ->
    canvas.clearRect(0, 0, canvas.elem.width, canvas.elem.height)

generate_key_widths = () ->
    keyWidths = []

    for note, index in NOTES
        lastNote = NOTES[index-1]
        nextNote = NOTES[index+1]

        if note.white
            width = KEY_WIDTH
            if lastNote? and not lastNote.white
                width -= KEY_WIDTH/4
            if nextNote? and not nextNote.white
                width -= KEY_WIDTH/4
        else
            width = KEY_WIDTH/2

        keyWidths.push(width)

    return keyWidths

get_note_magnitudes = (analyser, freqBins) ->
    freqByteData = new Uint8Array(analyser.frequencyBinCount)
    analyser.getByteFrequencyData(freqByteData)
    # normalize freq data
    freqData = (point/255 for point in freqByteData)
    magnitudes = convert_to_note_magnitudes(freqData, freqBins)
    return (Math.pow(m, 4) for m in magnitudes)

setup_spectrogram = (analyser) ->
    spectrogram = create_context(NOTES.length * KEY_WIDTH + 1, SPECTROGRAM_ROW_HEIGHT * SPECTROGRAM_ROWS)
    keyWidths = generate_key_widths()
    freqBins = gen_freq_bins(window.audio.sampleRate, analyser.frequencyBinCount, analyser.fftSize)

    stored_magnitudes = []
    set_interval UPDATE_PERIOD, ->
        magnitudes = get_note_magnitudes(analyser, freqBins)
        stored_magnitudes.push(magnitudes)
        draw_spectrogram()

    draw_spectrogram = () ->
        clear_canvas(spectrogram)

        if stored_magnitudes.length < SPECTROGRAM_ROWS
            row = stored_magnitudes.length
        else
            row = SPECTROGRAM_ROWS

        for magnitudes in stored_magnitudes[-SPECTROGRAM_ROWS..]
            y_offset = row * SPECTROGRAM_ROW_HEIGHT
            x_offset = 0
            for note, index in NOTES
                width = keyWidths[index]

                magnitude = magnitudes[index]
                redness = Math.round(magnitude * 255)
                spectrogram.fillStyle = "rgb(255,#{255-redness},#{255-redness})"
                spectrogram.fillRect(x_offset, y_offset, width, SPECTROGRAM_ROW_HEIGHT)

                x_offset += width

            row -= 1

setup_keyboard = (analyser) ->
    keyHeight = KEY_WIDTH * 4
    # 52 white keys
    keyboard = create_context(52 * KEY_WIDTH + 1, keyHeight * 1.5)
    keyWidths = generate_key_widths()
    freqBins = gen_freq_bins(window.audio.sampleRate, analyser.frequencyBinCount, analyser.fftSize)

    draw_keyboard = () ->
        magnitudes = get_note_magnitudes(analyser, freqBins)

        clear_canvas(keyboard)

        offset = 0
        for note, index in NOTES
            if note.white
                keyboard.fillStyle = "rgb(0,0,0)"
                # + 1 is to draw last line on the right hand side of the keyboard
                # the other keys are overdrawn by the key to the right
                keyboard.fillRect(offset, 0, KEY_WIDTH + 1, keyHeight)
                magnitude = magnitudes[index]
                redness = Math.round(magnitude * 255)
                keyboard.fillStyle = "rgb(255,#{255-redness},#{255-redness})"
                keyboard.fillRect(offset+1, 1, KEY_WIDTH - 1, keyHeight - 2)

                offset += KEY_WIDTH

        # draw black keys second since they overlay the white keys
        offset = 0
        for note, index in NOTES
            if note.white
                offset += KEY_WIDTH
            else
                magnitude = magnitudes[index]
                redness = Math.round(magnitude * 255)
                keyboard.fillStyle = "rgb(#{redness},0,0)"
                keyboard.fillRect(offset - KEY_WIDTH*0.25, 0, KEY_WIDTH/2, keyHeight*0.6)

    return draw_keyboard

main = ->
    window.audio = new webkitAudioContext()

    await load_audio("/glasswindow.wav", defer response)

    window.source = audio.createBufferSource()
    source.buffer = audio.createBuffer(response, false)

    spectrumAnalyser = audio.createAnalyser()
    spectrumAnalyser.fftSize = 2048
    spectrumAnalyser.smoothingTimeConstant = 0

    source.connect(spectrumAnalyser)

    # audio and keyboard display will be done off of a delay line
    delayTime = UPDATE_PERIOD / 1000 * SPECTROGRAM_ROWS
    delay = audio.createDelay(delayTime)
    delay.delayTime.value = delayTime

    source.connect(delay)
    delay.connect(audio.destination)

    keyboardAnalyser = audio.createAnalyser()
    keyboardAnalyser.fftSize = 2048
    keyboardAnalyser.smoothingTimeConstant = 0.2

    delay.connect(keyboardAnalyser)

    setup_spectrogram(spectrumAnalyser)
    draw_keyboard = setup_keyboard(keyboardAnalyser)

    draw = ->
        window.requestAnimationFrame(draw)
        draw_keyboard()

    window.start = ->
        window.requestAnimationFrame(draw)
        source.start(0)

    window.stop = ->
        source.stop(0)

    window.start()

load_audio = (url, cb) ->
    request = new XMLHttpRequest()
    request.open("GET", url, true)
    request.responseType = "arraybuffer"

    request.onload = ->
        cb(request.response)

    request.send()


$(document).ready ->
    main()
