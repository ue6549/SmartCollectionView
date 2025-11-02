<!-- b92086a4-0b5f-4265-8956-90e307ea0909 cb3d7dc3-5f5a-4cfb-8716-a44212adab2a -->
# Shadow-Node Virtualization (Option A)

## Goal
Move SmartCollectionView to a shadow-node–driven virtualization flow so Yoga never lays out the actual child views. Shadow nodes produce metadata, the native view mounts only visible wrappers, and horizontal layout remains stable.

## Steps
1. **Shadow Metadata Pipeline**
   - Extend `SmartCollectionViewShadowView` to gather per-item specs (reactTag/key, layout metrics, intrinsic size estimate, margins, version).
   - Hook into shadow layout so we mark the data dirty and publish a metadata array whenever inserts/removals/layout changes happen.

2. **Bridge Metadata to Native View**
   - In `SmartCollectionViewManager`, return the custom shadow view and forward metadata to `SmartCollectionView` through `setLocalData:`.
   - Stop handing off real child UIViews. Native side will request the children by tag when needed.

3. **SmartCollectionView Refactor**
   - Swap `_virtualItems` for metadata storage; maintain wrapper pools keyed by layout type.
   - For each visible index, create/recycle a wrapper, ask `RCTUIManager` to mount the corresponding React child into it, and position using our layout provider.
   - Remove the “reapply frames” hack; layout should stay horizontal because Yoga no longer touches the actual views.

4. **Unmount & Recycling**
   - When an item leaves the window, detach the React child from the wrapper and return the wrapper to the pool for reuse.

5. **Validation & Cleanup**
   - Add temporary logging (shadow frame vs mounted frame) to verify the pipeline, then clean up debug output once confirmed.

## Follow-ups
- React child reuse (keeping RN subtrees alive and rebinding props) once virtualization is stable.
- Additional layout providers (grids, waterfall) leveraging the same metadata pipeline.

