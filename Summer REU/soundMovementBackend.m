%This script holds more functions for chopping and implementing the sounds
%for the study

%MISSING --------------------------------------------------------------
%Having the drive play the control values
%Crossfading

%Global Variables
fs = 44100; %Hz
hrtfresolution = 5; %degrees
movementSpeeds = [10 20 40 80 160 320]; %in degrees/sec
movementAngles = [5 20 40 60 90 120]; %in degrees
controlSpeed = 0; controlAngle = 0;


driver('D:\Users\Lab User\Desktop\MAMA Experiment\HRTFs\hrir20_final.mat', ...
    movementSpeeds,movementAngles, fs, hrtfresolution);



%Driver for all the different testing conditions

function driver = driver(HRTFToUse, movementSpeeds, movementAngles, fs, hrtfresolution) 
    triangle = audioread('Sounds/triangle.mp3');
    noisy = audioread('Sounds/noisy.mp3');
    farTriangle = audioread('Sounds/farTriangle.mp3');
    farNoisy = audioread('Sounds/farNoisy.mp3');
    sounds = [triangle noisy farTriangle farNoisy];
    for sound = 1:(width(sounds))/2
        for speed = 1:length(movementSpeeds)
            for angle = 1:length(movementAngles)
                out = ['sound: ',num2str(sound),' speed: ',num2str(movementSpeeds(speed)),' angle: ', num2str(movementAngles(angle))];
                disp(out)
                onoffset = calculateOnOffset(movementAngles(angle), hrtfresolution);
                inputSound = sounds(:,sound*2 -1:sound*2);
                chopped = createMovement(inputSound, fs, movementSpeeds(speed), movementAngles(angle), hrtfresolution);
                %Some type of wait for ping from UI to play the next sound.
                %This is where it would communicate with the Front end
                onset = (onoffset(1) - 90) %converts from coordinate system interface uses to HRTF coordinate system
                offset = (onoffset(2) - 90)
                playSound(chopped, fs, onset, offset, HRTFToUse, hrtfresolution);
                pause(1); %FOR TESTING ONLY, PAUSING EXECUTION ----------
            end
        end
%         controlSound = sounds(:,1+(sound-1)*2);
%         playSound(controlSound(1:(fs/2)), fs, 0, 0, HRTFToUse, hrtfresolution); %Play the control 
    end
    driver = 1;
end



%Create a random onset and offset angle within 0 and 180 degrees with
%random direction
%
%Inputs: angle of movement in degrees and the resolution of hrtf database in degrees
%Output: [onsetangle offsetangle]

function info = calculateOnOffset(angle, hrtfresolution)
    while true
        onset = randi(181) - 1; %random integer between 0 and 180
        onset = round(onset / hrtfresolution) * hrtfresolution; %rounds to nearest 5
        possibleDirections = [-1 1]; %possible directions
        direction = possibleDirections(randi(2)); %sets a random direction
        offsetBuffer = onset + direction * angle;
        if (offsetBuffer >= 0) && (offsetBuffer <= 180) %makes sure angle doesn't go out of bounds
            offset = offsetBuffer;
        else
            offset = onset - direction * angle;
        end
        info = [onset offset];
        if (offset >=0) && (offset <= 180)
            break
        end
    end
end


%This will act as the backend processing for generating a moving sound
%returns a matrix where every row is a clip of the sound to play at a
%particular point
%
%inputs: the input sound signal, sample rate, speed of movement, angle of
%movement, and resolution of the hrtf database
%outputs: Sound represented as a matrix divided into rows

function chopped = createMovement(inputSound, fs, speed, angle, hrtfresolution)
    points = (angle/hrtfresolution) + 1; %gets the number of points needed to create the moving effect
    N = ceil(points * (hrtfresolution / speed) * fs); %number of samples needed to make the movement
    %Zero padding if the array size is funky at the end _-------------
    audioClip = inputSound(1:N); %takes that many samples from input signal
    remainder = mod(N,points);
    audioClip = [audioClip zeros(1,points - remainder)];
    shaped = reshape(audioClip,[],points); %each column becomes audio to play at a point
    chopped = transpose(shaped);
end

%This will act as the backend processing for playing a moving sound
%
%inputs: the chopped input signal, sample rate, onset angle, offset angle, speed of movement, 
% and resolution of the hrtf database
%outputs: Sound represented as a matrix divided into rows

function p = playSound(chopped, fs, onset, offset, HRTFToUse, hrtfresolution)
    %Load HRTF (HRIR)
    load(HRTFToUse);
    
    %25 locations
    azimuths = [-80 -65 -55 -45:5:45 55 65 80];
    
    %25 locations
    elevations = -45 + 5.625*(0:24);

    %desired 37 locations
    desiredAzimuths = -90:hrtfresolution:90;
    
    %desired 37 locations
    desiredElevations = -45 + 5.625*(0:36);

    eIndex = 9; %1 to 25  9 marks the zero
    
    %HRTF NEEDS TO BE FORMATTED IN A CERTAIN WAY --------------------
    
    leftChannel = hrir_l(:,eIndex,:);
    rightChannel = hrir_r(:,eIndex,:);
    interpolated = interpolateHRTF([leftChannel rightChannel], [azimuths' elevations'], [desiredAzimuths' desiredElevations']); %interpolates HRTF
    hrir_l = interpolated(:,1,:);
    hrir_r = interpolated(:,2,:);
    
    aIndex = 19; %1 to 37  13 marks the zero

    
    aOnset = aIndex + onset/hrtfresolution;  %marks index for onset angle
    aOffset = aIndex + offset/hrtfresolution; %marks index for offset angle
    if (aOnset > aOffset)
        aVector = aOnset:-1:aOffset;
    else
        aVector = aOnset:1:aOffset;
    end
    
    rows = height(chopped); %number of rows
    wav_left = [];
    wav_right = [];
    for i = 1:rows
        lft = squeeze(hrir_l(aVector(i), :, :));
        rgt = squeeze(hrir_r(aVector(i), :, :));
        
        delay = ITD(aIndex, eIndex); %calculates ITD charactaristics
        
        if(aIndex < 13) %We need a way to exadurate the IID cues
            lft = [lft' zeros(size(1:abs(delay)))];
            rgt = [zeros(size(1:abs(delay))) rgt'];
        else 
            lft = [zeros(size(1:abs(delay))) lft'];
            rgt = [rgt' zeros(size(1:abs(delay)))];
        end
        wav_left = [wav_left, conv(lft, chopped(i,:))]; % BIGGEST PROBLEM NOT CONCATINATING
        wav_right = [wav_right, conv(rgt, chopped(i,:))];
    end
    sectionDuration = size(chopped(1,:))/fs;
    sectionDuration = sectionDuration(2);


    %Crossfading needs to be done -------------

%     left = squeeze(hrir_l(:, eIndex, :));
%     left = reshape(left,[],1);
%     right = squeeze(hrir_r(:, eIndex, :));
%     right = reshape(right,[],1);
%     binaural = crossfading(wav_left, 100, sectionDuration, left, right);
%                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           
    soundToPlay(:,1) = wav_left;
    soundToPlay(:,2) = wav_right; 
    soundsc(soundToPlay, fs);
    p = 1;
end

% crossfading 
function binaural = crossfading(sound2fade, overlapSamples, duration, hrirL, hrirR)
    durationPerPosition = duration; %1; %in seconds
    f_s = 44100;
    n=overlapSamples; %100; % overlaps samples, should I make this 199?
    sample_length = f_s*durationPerPosition;
    W = linspace(1,0,n)'; %creates 100 evenly spaced numbers from 1 to 0 
    %I need to see what sound I need to put here
    sound = sound2fade; %[sound,f_s]=audioread('render/Emotion_normalize.wav'); 
    left_hrir = hrirL;
    right_hrir = hrirR;

    % sound=sound(1:1893960);
%     [sound_dft,F] = freqz(sound,1,256,f_s); %256 is the # of eval pts
%     % plot magnitude
%     plot(F,20*log10(abs(sound_dft))); %why is F not being divided by pi?
    % x = ones(3096,1);
    % xw=x.*W;
    for i = 2: size (left_hrir,1)
        if i ==2 
    %         left
            left_channel_previous = conv2(sound((i-1):(i-1)*sample_length),left_hrir(i-1,:)','valid');
            left_channel_current = conv2(sound((i-1)*sample_length+1:i*sample_length),left_hrir(i,:)','valid');
            left_channel_1 = left_channel_previous;
            %what is end?!
            left_channel_1(end-n+1:end) = left_channel_previous(end-n+1:end).*W; %I'm getting an error b/c of this n
            left_channel_2 = left_channel_current;
            left_channel_2(1:n) = left_channel_current(1:n).*(1-W);
            left_channel_previous = left_channel_2;
            
            binaural_left=[ left_channel_1(1:end-n);left_channel_1(end-n+1:end)+left_channel_2(1:n);left_channel_2(n+1:end-n)];
    %         binaural_left = binaural_left./max(abs(binaural_left));
    %         right
            right_channel_previous = conv2(sound((i-1):(i-1)*sample_length),right_hrir(i-1,:)','valid');
            right_channel_current = conv2(sound((i-1)*sample_length+1:i*sample_length),right_hrir(i,:)','valid');
            right_channel_1 = right_channel_previous;
            right_channel_1(end-n+1:end) = right_channel_previous(end-n+1:end).*W;
            right_channel_2 = right_channel_current;
            right_channel_2(1:n) = right_channel_current(1:n).*(1-W);
            right_channel_previous = right_channel_2;
            
            binaural_right=[ right_channel_1(1:end-n);right_channel_1(end-n+1:end)+right_channel_2(1:n);right_channel_2(n+1:end-n)];
    %         binaural_right = binaural_right./max(abs(binaural_right));
        end
     
        if i> 2
    %         left
            left_channel_current = conv2(sound((i-1)*sample_length+1:i*sample_length),left_hrir(i,:)','valid');
            left_channel_1 = left_channel_previous ;
            left_channel_1(end-n+1:end) = left_channel_previous(end-n+1:end).*W;
            left_channel_2 = left_channel_current;
            left_channel_2(1:n) = left_channel_current(1:n).*(1-W);
            left_channel_previous = left_channel_2;
    
            binaural_left = [ binaural_left; 
                left_channel_1(end-n+1:end)+left_channel_2(1:n);left_channel_2(n+1:end-n)];
            
    %         right
            right_channel_current = conv2(sound((i-1)*sample_length+1:i*sample_length),right_hrir(i,:)','valid');
            right_channel_1 = right_channel_previous ;
            right_channel_1(end-n+1:end) = right_channel_previous(end-n+1:end).*W;
            right_channel_2 = right_channel_current;
            right_channel_2(1:n) = right_channel_current(1:n).*(1-W);
            right_channel_previous = right_channel_2;
    
            binaural_right = [ binaural_right; right_channel_1(end-n+1:end)+right_channel_2(1:n);right_channel_2(n+1:end-n)];
            
        end
           
    end
    binaural = [binaural_left * max(sound(:))/max(abs(binaural_left(:))),binaural_right*max(sound(:))./max(abs(binaural_right(:)))]; 
     
    %audio_name = ['render/render_',num2str(durationPerPosition),'s_',file_name,'.wav'];
     
    %audiowrite(audio_name,binaural,f_s);
end