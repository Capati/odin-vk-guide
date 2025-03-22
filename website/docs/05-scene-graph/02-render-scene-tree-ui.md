---
sidebar_position: 2
sidebar_label: "Render Scene Tree UI"
---

# Render Scene Tree UI

This tutorial will guide you through creating a scene tree  viewer using ImGui. We'll build a
simple tree view for our scene graph that displays nodes, supports selection, and handles
parent-child relationships.

## Main Window Setup

The `engine_ui_definition` procedure from `drawing.odin` is where we set up the ImGui window
that will house our scene tree.

```odin title="drawing.odin"
engine_ui_definition :: proc(self: ^Engine) {
    // imgui new frame
    im_glfw.new_frame()
    im_vk.new_frame()
    im.new_frame()

    v := im.get_main_viewport()
    im.set_next_window_pos({0, 0})
    im.set_next_window_size({250, v.work_size.y})
    im.begin("Scene Graph", nil, {.No_Focus_On_Appearing, .No_Collapse, .No_Resize})
    @(static) selected_node: i32 = -1
    for &hierarchy, i in self.scene.hierarchy {
        if hierarchy.parent == -1 {
            render_scene_tree_ui(&self.scene, i, &selected_node)
        }
    }
    im.end()

    //make imgui calculate internal draw structures
    im.render()
}
```

1. We begin by configuring the window's position and size based on the main viewport, placing it
at top left, with a fixed width of 250 pixels and a height that spans the viewport's working
area.

    ```odin
    v := im.get_main_viewport()
    im.set_next_window_pos({0, 0})
    im.set_next_window_size({250, v.work_size.y})
    ```

2. The window, titled "Scene Graph," is created with flags that prevent it from being resized,
   collapsed, or focused on appearance, giving it a stable, docked appearance.

    ```odin
    im.begin("Scene Graph", nil, {.No_Focus_On_Appearing, .No_Collapse, .No_Resize})
    ```

3. Inside this window, we define a static variable `selected_node` to track the currently
   selected node across frames, then iterate through the scene's hierarchy to find and render
   root nodes.

    ```odin
    @(static) selected_node: i32 = -1
    for &hierarchy, i in self.scene.hierarchy {
        if hierarchy.parent == -1 {
            render_scene_tree_ui(&self.scene, i, &selected_node)
        }
    }
    ```

## Scene Tree Rendering

The `render_scene_tree_ui` procedure is responsible for rendering the scene tree with ImGui. It
handles displaying individual nodes, managing their appearance, detecting user interactions,
and traversing the hierarchy.

```odin
render_scene_tree_ui :: proc(scene: ^Scene, #any_int node: i32, selected_node: ^i32) -> i32 {
    name := scene_get_node_name(scene, node)
    label := len(name) == 0 ? "NO NODE" : name
    is_leaf := scene.hierarchy[node].first_child < 0
    flags: im.Tree_Node_Flags = is_leaf ? {.Leaf} | {.Bullet} : {}

    if node == selected_node^ {
        flags += {.Selected}
    }

    // Make the node span the entire width
    flags += {.Span_Full_Width}

    is_opened := im.tree_node_ex_ptr(&scene.hierarchy[node], flags, "%s", cstring(raw_data(label)))

    // Check for clicks in the entire row area
    was_clicked := im.is_item_clicked()

    im.push_id_int(node)
    {
        if was_clicked {
            log.debugf("Selected node: %d (%s)", node, label)
            selected_node^ = node
        }

        if is_opened {
            for ch := scene.hierarchy[node].first_child;
                ch != -1;
                ch = scene.hierarchy[ch].next_sibling {
                if sub_node := render_scene_tree_ui(scene, ch, selected_node); sub_node > -1 {
                    selected_node^ = sub_node
                }
            }
            im.tree_pop()
        }
    }
    im.pop_id()

    return selected_node^
}
```

Here's how it works, broken down into clear steps:

1. We start by retrieving the node's name and determining whether it's a leaf node. The name is
   fetched using a helper procedure `scene_get_node_name`, and if it's empty, we default to "NO
   NODE". We then check if the node is a leaf by examining its `first_child` field—
   if it's less than `0`, there are no children, marking it as a leaf.

    ```odin
    name := scene_get_node_name(scene, node)
    label := len(name) == 0 ? "NO NODE" : name
    is_leaf := scene.hierarchy[node].first_child < 0
    ```

    This is the code for `scene_get_node_name`, place into `scene.odin`:

    ```odin
    scene_get_node_name :: proc(self: ^Scene, #any_int node: i32) -> string {
        name_idx := self.name_for_node[u32(node)]
        if name_idx == NO_NAME {
            return ""
        }
        return self.node_names[name_idx]
    }
    ```

2. Next, we configure the ImGui tree node flags to control its behavior and appearance. For
   leaf nodes, we set the `.Leaf` flag to remove the expand arrow and add `.Bullet` for a small
   visual marker. If the current node matches the selected node, we include the `.Selected` flag
   to highlight it. Finally, we add `.Span_Full_Width` to make the node stretch across the
   window, ensuring the entire row is clickable.

    ```odin
    flags: im.Tree_Node_Flags = is_leaf ? {.Leaf, .Bullet} : {}
    if node == selected_node^ {
        flags += {.Selected}
    }
    flags += {.Span_Full_Width}
    ```

3. We them create the node using `im.tree_node_ex_ptr`, passing the node pointer, flags, and the
   label as a formatted string.

    ```odin
    is_opened := im.tree_node_ex_ptr(
        &scene.hierarchy[node],
        flags,
        "%s",
        cstring(raw_data(label)),
    )
    ```

4. After rendering, we check for user interaction and handle node selection. We use
   `im.is_item_clicked()` to detect if the node was clicked. To ensure ImGui widgets have unique
   IDs, we push the node's index onto the ID stack. If a click is detected, we log the
   selection and update the `selected_node` pointer with the current node's index.

    ```odin
    // Check for clicks in the entire row area
    was_clicked := im.is_item_clicked()

    im.push_id_int(node)
    {
      if was_clicked {
          log.debugf("Selected node: %d (%s)", node, label)
          selected_node^ = node
      }
    ```

5. If the node is expanded (i.e., `is_opened` is `true`), we recursively render its children.
   We start with the `first_child` of the current node and iterate through all siblings using
   the `next_sibling` field. For each child, we call `render_scene_tree_ui` recursively,
   passing the same scene and selected node pointer. If a child returns a selected node index
   greater than `-1`, we update `selected_node` with that value. After rendering all children,
   we call `im.tree_pop()` to close the tree node.

    ```odin
    if is_opened {
        for ch := scene.hierarchy[node].first_child;
            ch != -1;
            ch = scene.hierarchy[ch].next_sibling {
            if sub_node := render_scene_tree_ui(scene, ch, selected_node); sub_node > -1 {
                selected_node^ = sub_node
            }
        }
        im.tree_pop()
    }
    ```

6. Finally, we pop the ID stack to avoid conflicts with other nodes, ensuring ImGui's internal
   state remains consistent. The procedure returns the current value of `selected_node`, which
   could have been updated either by clicking the current node or by a selection in one of its
   children.

    ```odin
    im.pop_id()
    return selected_node^
    ```

This is the end result for this section:

![Scene Tree Rendering](./img/scene_tree_rendering.png)

## Conclusion

Our tree view might not have editing options yet, but it’s a great starting point for
integrating scene graphs into the engine, setting the framework for more advanced functionality
in upcoming chapters.
