#!/usr/bin/env perl

use strict;
use constant MIN_INTERVAL => 31.0;
use File::Temp 'tempfile';

if (@ARGV < 2) {
    print STDERR "Usage: $0 [INPUT] [OUTPUT]\n";
    exit 1;
}

# get original metadata and open it in append mode
my ($tmpfh, $tmpfile) = tempfile;
close $tmpfh;
`ffmpeg -v quiet -y -i $ARGV[0] -f ffmetadata $tmpfile`;
die "cannot get the original metadata: $!" if $?;
open(MD, ">> $tmpfile");

my $last_time = 0;
my $last_chapter_start_time = 0;
my $start_time = 0;

# silence detect
open(SD, "ffmpeg -hide_banner -nostats -y -i $ARGV[0] -af 'silencedetect=d=.5' -c:v copy -c:a pcm_dvd -f null - 2>&1 | grep 'silence_start' |") or die "cannot detect silence: $!";
while (<SD>) {
    ($start_time) = (/^.*silence_start: ([0-9\.]+).*$/);
    if (($start_time - $last_time) > MIN_INTERVAL) {
        # set chapter
        if ($last_chapter_start_time != $last_time) {
            # set chapter at the end of CM
            print MD "[CHAPTER]\n";
            print MD "TIMEBASE=1/1000\n";
            printf MD "START=%d\n", ($last_chapter_start_time * 1000);
            printf MD "END=%d\n", ($last_time * 1000);
            $last_chapter_start_time = $last_time;
        }
        print MD "[CHAPTER]\n";
        print MD "TIMEBASE=1/1000\n";
        printf MD "START=%d\n", ($last_chapter_start_time * 1000);
        printf MD "END=%d\n", ($start_time * 1000);
        $last_chapter_start_time = $start_time;
    }
    $last_time = $start_time;
}
if ($last_chapter_start_time != $start_time) {
    print MD "[CHAPTER]\n";
    print MD "TIMEBASE=1/1000\n";
    printf MD "START=%d\n", ($last_chapter_start_time * 1000);
    printf MD "END=%d\n", ($start_time * 1000);
}
close(SD);
close(MD);

# set chapters
`ffmpeg -v quiet -y -i $ARGV[0] -i $tmpfile -movflags faststart -map_metadata 1 -codec copy "$ARGV[1]"`;
die "cannot set chapters: $!" if $?;

# delete tmpfile
unlink $tmpfile;
