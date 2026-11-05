# Where TRACE can go next

Research and product decisions, 5 November 2026.

TRACE is most useful when a short hand movement becomes something you can inspect, edit, and use elsewhere. The immediate audience is a designer studying an interaction, an animator checking a gesture, or a researcher preparing a small motion sample. The changes in 0.2 support that workflow.

## What informed this update

| Source | Useful finding | Decision for TRACE |
| --- | --- | --- |
| [Apple: spatial layout](https://developer.apple.com/design/human-interface-guidelines/spatial-layout/) | Center important immersive content and use depth with restraint. Small floating text can become hard to read. | Use one large, stationary countdown digit. Remove the circular backing and surrounding captions. Keep normal instructions in the console. |
| [Apple: generating a text mesh](https://developer.apple.com/documentation/realitykit/meshresource/generatetext(_:extrusiondepth:font:containerframe:alignment:linebreakmode:)) | RealityKit can generate extruded text with a frame sized to its actual content. | Cache the three numeral meshes and center them from their bounds. There is no circular clipping mask. |
| [Apple: ManipulationComponent](https://developer.apple.com/documentation/realitykit/manipulationcomponent) | Native object manipulation supports moving, rotating, and resizing, with a choice of release behavior. | On visionOS 26 and later, the recording's ring redirects input to a stable pivot. The recording stays where it is released. View controls remain available on earlier versions. |
| [Apple: transforming entities with gestures](https://developer.apple.com/documentation/realitykit/transforming-realitykit-entities-with-gestures) | Translation, rotation, and scale belong to an entity's display transform. | Put replay content beneath a separate inspection pivot. Keep the captured stage coordinates intact. |
| [Blender: motion paths](https://docs.blender.org/manual/en/latest/animation/motion_paths.html) | Paths make the movement of a point or bone across frames visible. | Add optional full index-fingertip paths. Break the line at missing, inferred, or widely separated samples. |
| [Apple: document-based SwiftUI](https://developer.apple.com/documentation/swiftui/building-a-document-based-app-with-swiftui/) | File documents and the system exporter let the person choose a destination. | Offer CSV and JSON in the main window after leaving immersion. Export happens only after a deliberate action. |
| [robomimic: dataset structure](https://robomimic.github.io/docs/datasets/overview.html) | Robot demonstrations include environment observations and action sequences, not just human joint positions. | Keep this release's export honest: stage-relative human motion with confidence flags. Robot control needs a separate adapter and validation. |
| [LeRobot: dataset API](https://huggingface.co/docs/lerobot/main/api/datasets) | Dataset collection is organized into frames and episodes, with feature definitions, task context, and timestamps. | Preserve time, hand identity, units, and confidence in exports. A future collection workflow should add task labels and session metadata. |

The feature choices below are product judgments based on those sources and the existing app. They are not evidence of market demand or claims of scientific accuracy.

## Shipped in 0.2

**An uncluttered countdown.** A dark, extruded numeral sits above the action. The console keeps a cancel button and an accessible remaining-time value. The digits do not move toward the wearer or pulse in depth.

**Inspection from any side.** Turn through 360 degrees, tilt, resize, or jump to recorded, opposite, and side views. Reset restores the original presentation. Native manipulation is available from the visible ring on visionOS 26 and later. A large invisible collision box is deliberately avoided because it could intercept input meant for the console.

**A small editing workflow.** Set in and out points, repeat that region, reverse playback, and choose quarter, half, normal, or double speed. Save the selection as a new study. The original is retained. Interpolated boundary poses keep their tracking confidence.

**Paths you can inspect.** Optional index-fingertip paths show the complete recorded trajectory, including while playback is paused. Turning the study also turns its paths. Inferred or missing points do not get connected across a gap.

**Useful measurements.** Wrist travel, peak speed between samples, and the percentage of frames with a measured wrist are shown separately for each hand. These numbers exclude inferred joints and gaps over 150 milliseconds. Tracking noise can affect speed estimates. They are descriptive measurements, not a quality or health score.

**A route out of the app.** CSV gives scripts and spreadsheets one row per supplied joint. JSON preserves the study schema. Both keep the original coordinate system and confidence. View rotation and zoom never alter exported values. A missing hand remains explicit in CSV.

## Next experiments, in priority order

| Idea | Who benefits and why | First useful version | What needs resolving |
| --- | --- | --- | --- |
| Two-take comparison | A designer can compare two versions of the same gesture. | Load a second ghost, align starts, and scrub both on a shared timeline. | Separate timing differences from position differences. Let the wearer choose the alignment. |
| Pose bookmarks and annotations | A researcher can mark a hesitation, pinch, or failure during review. | Named time markers saved alongside a study. | Extend the schema without breaking older saved files. |
| Named tasks and recording sets | Repeated collection becomes easier to organize. | Group takes by task and mark keep or retry. | Naming, deletion, retention, and export of a whole set need a clear flow. |
| Confidence view | Developers can see where occlusion is affecting a pose. | A selectable joint overlay showing measured and inferred transforms. | Keep the overlay optional and readable without changing the hand surface. |
| Bimanual timing | Interaction designers can inspect coordination between hands. | Relative wrist distance and a shared motion timeline. | Explain missing data and avoid an invented accuracy percentage. |
| Blender importer | Animators can bring a study into a familiar editor. | Import CSV as labeled empties or curves, with meters and quaternion order documented. | Rig retargeting needs an explicit mapping and a repeatable bind pose. |
| Offline robot retargeting | Robotics teams can prototype how a human demonstration maps to a chosen robot. | A desktop adapter that converts a selected wrist path and gripper gesture into a simulated target. | Calibrate coordinate frames, choose inverse kinematics, define limits and gripper state, and validate in simulation before connecting hardware. |
| Shared review | Two people can discuss the same movement in space. | A synchronized playhead and shared take selection. | Align spatial references and obtain explicit permission before transferring motion data. |

## A sensible robotics boundary

The current CSV is useful for analysis and adapter development. It is not a LeRobot or robomimic training dataset and it does not send commands to a robot. Human hand joints do not define a robot's action space by themselves. A real integration needs the chosen robot, a calibrated frame transform, task observations, and a tested control layer. The dataset formats above make that missing context explicit.

## How to judge the next version

Have a few people record the same short task, find a moment, inspect its reverse side, save a segment, and export it without guidance. Note where they hesitate. On the headset, check native ring manipulation, panel reach, countdown visibility, dropped tracking, and sustained rendering. Those observations should decide whether comparison, labeling, or retargeting comes next.

Simulator tests establish the software path with synthetic data. They do not establish physical tracking fidelity, comfort, or headset frame rate.
