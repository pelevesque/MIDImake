#!/usr/bin/env raku

# Play two notes.

constant $ENDIANNESS = BigEndian;

my %bytes =
    'note-on'        => 0x90,
    'note-off'       => 0x80,
    'meta-event'     => 0xFF,
    'tempo'          => 0x51,
    'time-signature' => 0x58,
    'end-of-track'   => 0xF2,
;

sub write_2-bytes(UInt $int) { Buf.write-uint16(0, $int, $ENDIANNESS) }
sub write_4-bytes(UInt $int) { Buf.write-uint32(0, $int, $ENDIANNESS) }

sub make-header($buf, $format, $num-tracks, $time-division) {
    $buf.append: 'MThd'.ords;                   # header chunk ID
    $buf.append: write_4-bytes(6);              # constant: number of bytes remaining
    $buf.append: write_2-bytes($format);        # format type => 0 | 1 | 2
    $buf.append: write_2-bytes($num-tracks);    # number of tracks
    $buf.append: write_2-bytes($time-division); # time division
}

sub make-track($buf) {
    $buf.append: 'MTrk'.ords;                              # track chunk ID
    $buf.append: write_4-bytes(20);                        # number of bytes in track
    $buf.append: make-note-on( note => 0x3C, vol => 0x7F); # note-on
    $buf.append: make-note-off(note => 0x3C,  dt => 0x60); # note-off
    $buf.append: make-note-on( note => 0x3E, vol => 0x7F); # note-on
    $buf.append: make-note-off(note => 0x3E,  dt => 0x60); # note-off
    $buf.append: 0;                                        # delta time
    $buf.append: %bytes{'meta-event'};                     # meta event marker
    $buf.append: %bytes{'end-of-track'};                   # end of track event
    $buf.append: 0;                                        # end of track data
}

sub make-note-on(:$note, :$dt = 0, :$ch = 0, :$vol = 127) {
    my $code = %bytes{'note-on'} + $ch;
    $dt, $code, $note, $vol;
}

sub make-note-off(:$note, :$dt = 0, :$ch = 0, :$vol = 0) {
    my $code = %bytes{'note-off'} + $ch;
    $dt, $code, $note, $vol;
}

# Create the \ operator for time signatures.
# Ex: my $ts = 2\8;
#     say $ts.MIDI-denominator; # OUTPUT: «3␤»
sub infix:<\\>(UInt $numerator, UInt $denominator) {
    class TimeSignature {
        has UInt $.numerator is readonly;
        has UInt $.denominator is readonly;
        method WHAT() { 'TimeSignature' }
        method content() { $!numerator ~ "\\" ~ $!denominator }
        method print() { $!numerator ~ "/" ~ $!denominator }
        method MIDI-numerator() { $!numerator }
        method MIDI-denominator() { $!denominator.log(2) }
    }
    TimeSignature.new: :$numerator, :$denominator;
}

sub make-time-signature(
    :$time-signature = 4\4,
    :$num-MIDI-clocks-per-metronome-click = 24, # Is there a default?
    :$num_32nd-per-beat = 8
) {
    %bytes{'meta-event'},
    %bytes{'time-signature'},
    4, # constant: number of bytes remaining
    $time-signature.MIDI-numerator,
    $time-signature.MIDI-denominator,
    $num-MIDI-clocks-per-metronome-click,
    $num_32nd-per-beat;
}

subset UInt24 of UInt where * ≤ 16777215;
sub make-tempo(
    UInt24 :$ms-per-quarter-note = 500000 # MIDI default: => 120 BPM
) {
    my $buf = Buf.new();
    $buf.append: %bytes{'meta-event'};
    $buf.append: %bytes{'tempo'};
    $buf.append: 3; # constant: number of bytes remaining
    $buf.append: write_4-bytes($ms-per-quarter-note).splice(1);
}

sub MAIN () {
    my $buf = Buf.new();

    make-header($buf, 0, 1, 96);
    make-track($buf);

    spurt 'file.mid', $buf;
}

class MIDImake {
    subset Format where * ~~ 0 | 1 | 2;
    subset UInt8  of UInt where * ≤ 255;
    subset UInt16 of UInt where * ≤ 65535;
    subset UInt32 of UInt where * ≤ 4294967295;

    has Format $.format is rw;        # MIDI default: ?
    has UInt16 $.time-division is rw; # MIDI default: 48 ticks per quarter note

    constant $ENDIANNESS = BigEndian;

    method !write_2-bytes(UInt16 $uint16) {
        Buf.write-uint16(0, $uint16, $ENDIANNESS)
    }
    method !write_4-bytes(UInt32 $uint32) {
        Buf.write-uint32(0, $uint32, $ENDIANNESS)
    }

    method !make-header(:$num-tracks) {
        # It should throw an error if format or time-division is not set!
        'MThd'.ords,
        self!write_2-bytes($.format),
        self!write_4-bytes(6),
        self!write_2-bytes($num-tracks), # Auto calculate from track array!
        self!write_2-bytes($.time-division),
        ;
    }

    method render() { #`[send renderered bytes as string] }
}

# Ex:
my $mid = MIDImake.new();
$mid.format = 1;
$mid.time-division = 12;
