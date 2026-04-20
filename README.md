# StateMachinePlus

Advanced modular state machine system for scalable game logic.

## Overview

StateMachinePlus is a flexible and extensible system designed to manage complex state-driven behavior.

## Features

- Dynamic state transitions
- Event-driven structure
- State stacking support
- Clean lifecycle management

## Core Concepts

### State Lifecycle

Each state defines:
- Enter
- Update
- Exit

### Transitions

Controlled through logic conditions and events.

### State Stack

Supports layered logic:
- Push
- Pop

## Example

    local machine = StateMachine.new()

    machine:AddState("Idle", {
        Enter = function() end,
        Update = function() end,
        Exit = function() end
    })

    machine:SetState("Idle")

## Architecture

- Modular structure
- Separation of concerns
- Easy integration

## Use Cases

- NPC behavior
- Game flow
- Combat systems
- UI logic

## Philosophy

- Predictable behavior
- Maintainable code
- Scalable design

## Author

Matheus Souza
Roblox Systems Developer
