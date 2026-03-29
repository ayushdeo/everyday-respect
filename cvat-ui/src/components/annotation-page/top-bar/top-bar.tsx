// Copyright (C) 2020-2022 Intel Corporation
// Copyright (C) CVAT.ai Corporation
//
// SPDX-License-Identifier: MIT

import React, { useState } from 'react';
import { Col, Row } from 'antd/lib/grid';
import { SoundOutlined } from '@ant-design/icons';

import {
    ActiveControl, NavigationType, ToolsBlockerState, Workspace,
} from 'reducers';
import { Job } from 'cvat-core-wrapper';
import { KeyMap } from 'utils/mousetrap-react';
import { Chapter } from 'cvat-core/src/frames';
import LeftGroup from './left-group';
import PlayerButtons from './player-buttons';
import PlayerNavigation from './player-navigation';
import RightGroup from './right-group';
import AudioPlayer from './audio-player';

interface Props {
    playing: boolean;
    saving: boolean;
    chapters: Chapter[];
    hoveredChapter: number | null;
    frameNumber: number;
    frameFilename: string;
    frameDeleted: boolean;
    inputFrameRef: React.RefObject<HTMLInputElement>;
    startFrame: number;
    stopFrame: number;
    undoAction?: string;
    redoAction?: string;
    workspace: Workspace;
    undoShortcut: string;
    redoShortcut: string;
    drawShortcut: string;
    switchToolsBlockerShortcut: string;
    playPauseShortcut: string;
    deleteFrameShortcut: string;
    nextFrameShortcut: string;
    previousFrameShortcut: string;
    forwardShortcut: string;
    backwardShortcut: string;
    navigationType: NavigationType;
    focusFrameInputShortcut: string;
    searchFrameByNameShortcut: string;
    activeControl: ActiveControl;
    toolsBlockerState: ToolsBlockerState;
    annotationFilters: object[];
    initialOpenGuide: boolean;
    showSearchFrameByName: boolean;
    keyMap: KeyMap;
    jobInstance: Job;
    ranges: string;
    changeWorkspace(workspace: Workspace): void;
    showStatistics(): void;
    showFilters(): void;
    onSwitchPlay(): void;
    onPrevFrame(): void;
    onNextFrame(): void;
    onForward(): void;
    onBackward(): void;
    onFirstFrame(): void;
    onLastFrame(): void;
    onSearchAnnotations(direction: 'forward' | 'backward'): void;
    onSearchChapters(direction: 'forward' | 'backward'): void;
    onSelectChapter(id: number): void;
    setHoveredChapter(id: number | null): void;
    onSliderChange(value: number): void;
    onSliderCommit(value: number): void;
    onInputChange(value: number): void;
    onURLIconClick(): void;
    onCopyFilenameIconClick(): void;
    onUndoClick(): void;
    onRedoClick(): void;
    onFinishDraw(): void;
    onSwitchToolsBlockerState(): void;
    onDeleteFrame(): void;
    onRestoreFrame(): void;
    switchNavigationBlocked(blocked: boolean): void;
    setNavigationType(navigationType: NavigationType): void;
    switchShowSearchPallet(visible: boolean): void;
}

export default function AnnotationTopBarComponent(props: Props): JSX.Element {
    const {
        saving,
        undoAction,
        redoAction,
        playing,
        chapters,
        hoveredChapter,
        ranges,
        frameNumber,
        frameFilename,
        frameDeleted,
        inputFrameRef,
        startFrame,
        stopFrame,
        workspace,
        undoShortcut,
        redoShortcut,
        drawShortcut,
        switchToolsBlockerShortcut,
        playPauseShortcut,
        deleteFrameShortcut,
        nextFrameShortcut,
        previousFrameShortcut,
        forwardShortcut,
        backwardShortcut,
        focusFrameInputShortcut,
        searchFrameByNameShortcut,
        activeControl,
        toolsBlockerState,
        annotationFilters,
        initialOpenGuide,
        navigationType,
        jobInstance,
        keyMap,
        showStatistics,
        showFilters,
        changeWorkspace,
        onSwitchPlay,
        onPrevFrame,
        onNextFrame,
        onForward,
        onBackward,
        onFirstFrame,
        onLastFrame,
        onSearchAnnotations,
        onSearchChapters,
        onSelectChapter,
        setHoveredChapter,
        onSliderChange,
        onSliderCommit,
        onInputChange,
        onURLIconClick,
        onCopyFilenameIconClick,
        onUndoClick,
        onRedoClick,
        onFinishDraw,
        onSwitchToolsBlockerState,
        onDeleteFrame,
        onRestoreFrame,
        setNavigationType,
        switchNavigationBlocked,
        switchShowSearchPallet,
        showSearchFrameByName,
    } = props;

    const [isMuted, setIsMuted] = useState<boolean>(false);

    const playerItems: [JSX.Element, number][] = [];

    playerItems.push([(
        <PlayerButtons
            key='player_buttons'
            playing={playing}
            playPauseShortcut={playPauseShortcut}
            nextFrameShortcut={nextFrameShortcut}
            previousFrameShortcut={previousFrameShortcut}
            forwardShortcut={forwardShortcut}
            backwardShortcut={backwardShortcut}
            navigationType={navigationType}
            chapters={chapters}
            keyMap={keyMap}
            workspace={workspace}
            onPrevFrame={onPrevFrame}
            onNextFrame={onNextFrame}
            onForward={onForward}
            onBackward={onBackward}
            onFirstFrame={onFirstFrame}
            onLastFrame={onLastFrame}
            onSwitchPlay={onSwitchPlay}
            onSearchAnnotations={onSearchAnnotations}
            onSearchChapters={onSearchChapters}
            onHoveredChapter={setHoveredChapter}
            onSelectChapter={onSelectChapter}
            setNavigationType={setNavigationType}
        />
    ), 0]);

    playerItems.push([(
        <React.Fragment key='audio_player'>
            <div
                className='cvat-player-mute-button'
                onClick={() => setIsMuted(!isMuted)}
                style={{ fontSize: '18px', padding: '0 10px', cursor: 'pointer', display: 'flex', alignItems: 'center' }}
            >
                {isMuted ? (
                    <svg viewBox="64 64 896 896" focusable="false" data-icon="sound" width="1em" height="1em" fill="currentColor" aria-hidden="true"><path d="M622.3 490.6l103.2-103.3a8.03 8.03 0 00-11.3-11.3l-103.3 103.2-103.2-103.2a8.03 8.03 0 00-11.3 11.3l103.2 103.3-103.2 103.2a8.03 8.03 0 0011.3 11.3l103.2-103.2 103.3 103.2a8.03 8.03 0 0011.3-11.3l-103.2-103.2zM805 385.6c7.7-18.9 11.7-39.1 11.7-59.6 0-14.8-1.7-29.3-5.2-43.5l-59 13.9c1.9 9.5 2.9 19.3 2.9 29.3 0 14.5-3.3 28.5-9.4 41.5l59 18.4z"></path></svg>
                ) : (
                    <SoundOutlined />
                )}
            </div>
            <AudioPlayer isMuted={isMuted} />
        </React.Fragment>
    ), 5]);

    playerItems.push([(
        <PlayerNavigation
            key='player_navigation'
            startFrame={startFrame}
            stopFrame={stopFrame}
            playing={playing}
            chapters={chapters}
            hoveredChapter={hoveredChapter}
            ranges={ranges}
            frameNumber={frameNumber}
            frameFilename={frameFilename}
            frameDeleted={frameDeleted}
            deleteFrameShortcut={deleteFrameShortcut}
            focusFrameInputShortcut={focusFrameInputShortcut}
            searchFrameByNameShortcut={searchFrameByNameShortcut}
            inputFrameRef={inputFrameRef}
            keyMap={keyMap}
            workspace={workspace}
            onSliderChange={onSliderChange}
            onSliderCommit={onSliderCommit}
            onInputChange={onInputChange}
            onURLIconClick={onURLIconClick}
            onCopyFilenameIconClick={onCopyFilenameIconClick}
            onDeleteFrame={onDeleteFrame}
            onRestoreFrame={onRestoreFrame}
            switchNavigationBlocked={switchNavigationBlocked}
            switchShowSearchPallet={switchShowSearchPallet}
            showSearchFrameByName={showSearchFrameByName}
        />
    ), 10]);

    return (
        <Row justify='space-between'>
            <LeftGroup
                saving={saving}
                undoAction={undoAction}
                redoAction={redoAction}
                undoShortcut={undoShortcut}
                redoShortcut={redoShortcut}
                activeControl={activeControl}
                drawShortcut={drawShortcut}
                switchToolsBlockerShortcut={switchToolsBlockerShortcut}
                toolsBlockerState={toolsBlockerState}
                onUndoClick={onUndoClick}
                onRedoClick={onRedoClick}
                onFinishDraw={onFinishDraw}
                onSwitchToolsBlockerState={onSwitchToolsBlockerState}
                keyMap={keyMap}
            />
            <Col className='cvat-annotation-header-player-group'>
                <Row align='middle'>
                    { playerItems.sort((menuItem1, menuItem2) => menuItem1[1] - menuItem2[1])
                        .map((menuItem) => menuItem[0]) }
                </Row>
            </Col>
            <RightGroup
                workspace={workspace}
                jobInstance={jobInstance}
                annotationFilters={annotationFilters}
                initialOpenGuide={initialOpenGuide}
                changeWorkspace={changeWorkspace}
                showStatistics={showStatistics}
                showFilters={showFilters}
            />
        </Row>
    );
}
