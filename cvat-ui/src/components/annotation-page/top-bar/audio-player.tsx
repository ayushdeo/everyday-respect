// Copyright (C) 2024
//
// SPDX-License-Identifier: MIT

import React, { useEffect, useRef, useState } from 'react';
import { useSelector } from 'react-redux';
import { CombinedState } from 'reducers';

interface Props {
    isMuted: boolean;
}

export default function AudioPlayer(props: Props): JSX.Element {
    const { isMuted } = props;
    const audioRef = useRef<HTMLAudioElement>(null);
    const [audioUrl, setAudioUrl] = useState<string>('');

    const playing = useSelector((state: CombinedState) => state.annotation.player.playing);
    const frameNumber = useSelector((state: CombinedState) => state.annotation.player.frame.number);
    const delay = useSelector((state: CombinedState) => state.annotation.player.frame.delay);
    const jobInstance = useSelector((state: CombinedState) => state.annotation.job.instance);

    // Always-fresh refs so event handlers don't close over stale values
    const frameNumberRef = useRef(frameNumber);
    const delayRef = useRef(delay);
    const audioUrlRef = useRef(audioUrl);
    frameNumberRef.current = frameNumber;
    delayRef.current = delay;
    audioUrlRef.current = audioUrl;

    // isDragging: true while the user is holding the slider thumb.
    // Set by the 'mousedown' on the slider rail and cleared on 'audio:scrub-commit'.
    const isDraggingRef = useRef(false);

    // Seek-loop guard: true while a browser seek is in flight.
    const isSeekingRef = useRef(false);
    const pendingSeekTimeRef = useRef<number | null>(null);

    // ── 1. Load audio as Blob ─────────────────────────────────────────────────────────────
    // Bypasses Django REST's missing HTTP 206 Range support; Blob URLs seek instantly.
    useEffect(() => {
        if (!jobInstance?.taskId) return;
        let active = true;
        fetch(`/api/tasks/${jobInstance.taskId}/audio`)
            .then(res => res.blob())
            .then(blob => {
                if (active && blob.type.includes('audio')) {
                    setAudioUrl(URL.createObjectURL(blob));
                }
            })
            .catch(console.error);
        return () => { active = false; };
    }, [jobInstance?.taskId]);

    // ── 2. Mute ───────────────────────────────────────────────────────────────────────────
    useEffect(() => {
        if (audioRef.current) audioRef.current.muted = isMuted;
    }, [isMuted]);

    // ── 3. Drain seek queue via native 'seeked' event ─────────────────────────────────────
    useEffect(() => {
        const audio = audioRef.current;
        if (!audio) return;
        const handleSeeked = () => {
            isSeekingRef.current = false;
            if (pendingSeekTimeRef.current !== null) {
                const nextTime = pendingSeekTimeRef.current;
                pendingSeekTimeRef.current = null;
                if (Math.abs(audio.currentTime - nextTime) > 0.05) {
                    isSeekingRef.current = true;
                    audio.currentTime = nextTime;
                }
            }
        };
        audio.addEventListener('seeked', handleSeeked);
        return () => audio.removeEventListener('seeked', handleSeeked);
    }, []);

    // ── 4. Detect drag START on the CVAT timeline slider ─────────────────────────────────
    // We set isDraggingRef when the user presses down on the slider rail.
    useEffect(() => {
        const handleSliderPointerDown = (e: MouseEvent) => {
            if ((e.target as HTMLElement)?.closest('.cvat-player-slider')) {
                isDraggingRef.current = true;
            }
        };
        window.addEventListener('mousedown', handleSliderPointerDown, { capture: true });
        return () => window.removeEventListener('mousedown', handleSliderPointerDown, { capture: true });
    }, []);

    // ── 5. Drag COMMIT — single precise seek on pointer-up ───────────────────────────────
    // The container fires 'audio:scrub-commit' with the final frame in onAfterChange.
    useEffect(() => {
        const handleScrubCommit = (e: Event) => {
            isDraggingRef.current = false;
            const frame = (e as CustomEvent<{ frame: number }>).detail.frame;
            const audio = audioRef.current;
            if (!audio || !audioUrlRef.current) return;

            const fps = delayRef.current ? 1000 / delayRef.current : 25;
            const targetTime = Math.min(frame / fps, isNaN(audio.duration) ? Infinity : audio.duration);

            console.log(
                `[SCRUB-COMMIT] frame=${frame} target=${targetTime.toFixed(3)}s` +
                ` audio.currentTime=${audio.currentTime.toFixed(3)}s audio.seeking=${audio.seeking}`,
            );

            // Single authoritative seek
            isSeekingRef.current = true;
            pendingSeekTimeRef.current = null;
            audio.currentTime = targetTime;
        };

        window.addEventListener('audio:scrub-commit', handleScrubCommit);
        return () => window.removeEventListener('audio:scrub-commit', handleScrubCommit);
    }, []);

    // ── 6. Play / Pause — snap to frame on every play-resume ─────────────────────────────
    // KEY FIX: CVAT's chunk loader keeps playing=true in Redux while stalling frameNumber.
    // Audio runs ahead during those stalls. Snapping currentTime before audio.play()
    // closes the gap accumulated during buffer pauses.
    useEffect(() => {
        const audio = audioRef.current;
        if (!audio || !audioUrl) return;

        const fps = delayRef.current ? 1000 / delayRef.current : 25;
        const safeMax = isNaN(audio.duration) ? Infinity : audio.duration;
        const targetTime = Math.min(frameNumberRef.current / fps, safeMax);

        if (playing) {
            console.log(
                `[PLAY-RESUME] frame=${frameNumberRef.current} snap=${targetTime.toFixed(3)}s` +
                ` audio.currentTime=${audio.currentTime.toFixed(3)}s`,
            );
            audio.currentTime = targetTime;
            audio.play().catch(e => console.warn('AudioPlayer: play() blocked:', e));
        } else {
            audio.pause();
        }
    }, [playing, audioUrl]);

    // ── 7. Frame sync — scrub-while-paused only; skip during drag ────────────────────────
    // During intermediate slider drags, isDraggingRef is true — we skip all seeks.
    // Only when paused (non-drag frame changes: arrow-key, frame-input, etc.) do we seek.
    // During playback, large drift (>2s) is caught as a safety net.
    useEffect(() => {
        const audio = audioRef.current;
        if (!audio || !audioUrl) return;

        const fps = delay ? 1000 / delay : 25;
        const safeMax = isNaN(audio.duration) ? Infinity : audio.duration;
        const expectedTime = Math.min(frameNumber / fps, safeMax);

        if (!playing) {
            if (isDraggingRef.current) {
                // Slider drag in progress — audio:scrub-commit will handle the final seek
                return;
            }
            // Paused, non-drag change (arrow key, frame input, prev/next button)
            if (!isSeekingRef.current) {
                if (Math.abs(audio.currentTime - expectedTime) > 0.05) {
                    console.log(
                        `[FRAME-SEEK] frame=${frameNumber} expected=${expectedTime.toFixed(3)}s` +
                        ` audio.currentTime=${audio.currentTime.toFixed(3)}s`,
                    );
                    isSeekingRef.current = true;
                    audio.currentTime = expectedTime;
                }
            } else {
                pendingSeekTimeRef.current = expectedTime;
            }
        } else {
            // Playing — only large-drift safety net; play-resume snap (effect #6) handles normal sync
            if (!isSeekingRef.current && Math.abs(audio.currentTime - expectedTime) > 2.0) {
                console.warn(
                    `[DRIFT-CORRECTION] drift=${(audio.currentTime - expectedTime).toFixed(3)}s — snapping`,
                );
                isSeekingRef.current = true;
                audio.currentTime = expectedTime;
            }
        }
    }, [frameNumber, delay, playing, audioUrl]);

    if (!jobInstance || !audioUrl) return <></>;

    return (
        <audio
            ref={audioRef}
            src={audioUrl}
            preload="auto"
            style={{ display: 'none' }}
        />
    );
}
