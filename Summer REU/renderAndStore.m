%This script will render and store the sounds we'll use for our experiment

%The base of the sound will be a 12 second triangle wave at 400Hz

duration = 15; %seconds
fs = 44100; %Hz
frequency = 400; %Hz
t = 1:1/fs:duration - 1/fs; %time indexes in seconds

triangle = sawtooth(2 * pi * frequency * t, 0.5);
noisy = awgn(triangle, 20);
noisy = noisy / max(abs(noisy)); %normalize to avoid clipping

audiowrite('triangle.wav',triangle,fs);
audiowrite('noisy.wav',noisy,fs);



