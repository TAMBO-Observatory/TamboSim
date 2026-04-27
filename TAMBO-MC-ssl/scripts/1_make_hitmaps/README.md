# Making `hitmaps`

## First off, what is a `hitmap`, and why would you want to make one?

To answer the first question, an `hitmap` is a `Dict{DetectionModule, Vector{CorsikaEvent}}` mapping that tells you whether a particle from the `CORSIKA` simulation intersected a `DetectionModule` along its path.

[!CAUTION]
Our current intersection codde is a bit naive, and says that an intersection occured if and only if the particles intersection with the mountain is within the detection pannel.
This neglects the possibility of passing through the detection module on the way to the mountain.
This simplification should be fine for thin, panel-like detection modules, but may not hold for water tanks.

The intersection portion of the code is very time-consuming.
Thus, we want to decouple the intersection part of the code from the triggering part of the code, which is very fast.
This will let us study the impact of different trigger definitions and efficiencies on our event rate without having to rerun the intersection code each time.

## How do I run the code?

`WIP`
