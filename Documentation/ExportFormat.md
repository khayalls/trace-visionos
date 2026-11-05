# Motion export

CSV and JSON describe the selected study in its original stage coordinate system. An export contains human hand data, not robot commands.

## Coordinate and timing conventions

- Positions use meters in a fixed, Y-up stage.
- Quaternions use xyzw component order in that same stage.
- Frame time is elapsed seconds from the study's beginning. It is not a promise of perfectly regular sampling.
- Display rotation, translation, and scale are excluded from export.
- Trimming creates a new study and rebases its frame times to zero. It does not change the stage axes or spatial coordinates.

## CSV

```csv
source,coordinate_system,time_s,hand,hand_tracked,joint,joint_tracked,x_m,y_m,z_m,qx,qy,qz,qw
simulatorSample,stage-relative-meters-y-up-v1,0.000000,left,true,"wrist",true,-0.200000,1.430000,0.020000,0.000000,0.000000,0.000000,1.000000
simulatorSample,stage-relative-meters-y-up-v1,0.016667,left,false,,false,,,,,,,
```

The rows above are synthetic examples. A real export includes the actual supplied joint values.

| Field | Meaning |
| --- | --- |
| `source` | `device` or `simulatorSample` |
| `coordinate_system` | `stage-relative-meters-y-up-v1` |
| `time_s` | Actual sample time, formatted with six decimal places |
| `hand` | `left` or `right` |
| `hand_tracked` | Whether the hand anchor was tracked |
| `joint` | ARKit-mapped joint name; empty when the hand has no supplied joints |
| `joint_tracked` | Original joint confidence flag |
| `x_m`, `y_m`, `z_m` | Supplied stage-relative joint position |
| `qx`, `qy`, `qz`, `qw` | Supplied stage-relative orientation |

There is a row for every supplied joint, including inferred joints. A `false` confidence flag does not turn into `true` during export. Missing hands receive an empty-transform row, so a script can distinguish a gap from a zero-valued pose. Decimal formatting uses a fixed locale, and joint names are quoted and protected against spreadsheet formula interpretation.

## JSON

JSON uses the existing `MotionTake` Codable schema, with sorted keys and readable indentation. It preserves the schema version, generated study ID, creation date, title, source, hand selection, coordinate system, frames, provider state, joint transforms, and confidence flags. It can be decoded by the same model used for local persistence.

## Measurements and paths

Insights and visible paths use measured joints only. Wrist travel sums consecutive measured wrist segments; peak speed is the largest segment distance divided by its elapsed time. A missing or inferred wrist breaks continuity. Intervals longer than 150 ms do not contribute distance or speed. Coverage means the fraction of captured frames with a measured wrist, not a time-weighted sensor-availability measure.

The visible paths use the index fingertip. They are split at missing points, inferred points, and long gaps. The exported joint rows retain the original data even when those points are excluded from a visual path or measurement.

## Using the files

A spreadsheet or script can filter by hand and joint, then plot position against time. For animation, import meters and xyzw quaternions explicitly and map the joint names to the target rig. For robotics, define and validate a calibrated frame transform and an action representation for the chosen robot before attempting retargeting. This file alone is not a LeRobot or robomimic training dataset.
