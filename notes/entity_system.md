# Goals
- Trivially Parallelizable
  - Multithreading shouldn't require sync primitives everywhere
- Multiple Concurrent Physics Simulation
  - Jolt isn't designed to handle large world sims, so splitting up the sim is recommended, should this happen at world or entity level?
- Composable entities at component level, doesn't necessarily need to be runtime composable but that would be a bonus
- Fast and somewhat safe
  - Should not trigger tons of cache misses
  - Should be somewhat hard to get into invalid state (or invalid states shouldn't crash at least)
  - Ideally should be a data driven system

# Questions
- An ECS naively sounds like it would meet these requirements, Would it actually be good when trying to use entity hierarchy?
  - I have personally found hierarchies to be annoying in ECS, and it seems like they might be less cache-friendly
- SceneGraphs/EntityHierarchy tend to be slow and hard to thread, can we limit this and still produce the entity level composition? I.E. large spaceships made of smaller modules
- Can we learn anything from UE's entity system?

# Planned Components

## Rendering
- Static Mesh
- Skinned Mesh
- Light
- Camera
- Particle Emitter

## Physics
- RigidBody
- Collider
- Character
- Constraint

## Audio
- Source
- Sink

## Networking?
- IDK how to deal with Client Side Prediction and Rollbacks, good case for ECS?
- Do I even need to plan for this in the engine

## Lua
  - Script
