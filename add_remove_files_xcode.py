#!/usr/bin/env python3
"""
Universal Xcode project file manager that handles groups automatically.
Adds or removes files from any Xcode project, creating/managing groups as needed.
Supports target specification for adding files to specific targets.
"""

import sys
import os
from pathlib import Path
from argparse import ArgumentParser
from pbxproj import XcodeProject

def find_or_create_group(project, group_path_parts, parent=None):
    """
    Recursively find or create groups in the project structure.
    
    Args:
        project: The XcodeProject instance
        group_path_parts: List of group names representing the path (e.g., ['ServicePlugins', 'SubFolder'])
        parent: The parent group (None for root)
    
    Returns:
        The final group in the path
    """
    if not group_path_parts:
        return parent if parent else None
    
    current_group_name = group_path_parts[0]
    remaining_path = group_path_parts[1:]
    
    # Get or create the current group
    if parent:
        # Look for existing child group
        current_group = None
        for child in parent.children:
            if hasattr(child, 'name') and child.name == current_group_name:
                current_group = child
                break
        
        # Create if not found
        if not current_group:
            current_group = project.get_or_create_group(current_group_name, parent=parent)
    else:
        # Root level group - try to find or create
        current_group = project.get_or_create_group(current_group_name)
    
    # Recurse for remaining path
    if remaining_path:
        return find_or_create_group(project, remaining_path, current_group)
    else:
        return current_group

def get_group_path_for_file(project_root, file_path):
    """
    Determine the group path for a file based on its directory structure.
    
    Args:
        project_root: The root directory of the project
        file_path: The absolute path to the file
    
    Returns:
        A list of group names representing the path
    """
    try:
        # Get the relative path from project root
        relative_path = Path(file_path).relative_to(project_root)
        
        # Get the directory parts (excluding the filename)
        path_parts = list(relative_path.parent.parts)
        
        # Filter out special directories like '.' 
        path_parts = [p for p in path_parts if p != '.']
        
        return path_parts
    except ValueError:
        # File is not under project root
        return []

def get_target_by_name(project, target_name):
    """
    Find a target by name.
    
    Args:
        project: The XcodeProject instance
        target_name: Name of the target to find
    
    Returns:
        Target object or None if not found
    """
    for target in project.objects.get_targets():
        if target.name == target_name:
            return target
    return None

def add_file_with_groups(project, project_root, file_path, target_names=None):
    """
    Add a file to the project, creating necessary groups.
    
    Args:
        project: The XcodeProject instance
        project_root: The root directory of the project
        file_path: The absolute path to the file
        target_names: List of target names to add file to (None = all targets)
    """
    absolute_file_path = Path(file_path).resolve()
    relative_file_path = absolute_file_path.relative_to(project_root)
    
    # Determine the group path
    group_path = get_group_path_for_file(project_root, absolute_file_path)
    
    if group_path:
        # Find or create the necessary groups
        print(f"Creating/finding groups: {' > '.join(group_path)}")
        target_group = find_or_create_group(project, group_path)
        
        # Add the file to the specific group
        print(f"Adding file to group: {group_path[-1] if group_path else 'root'}")
    else:
        # Add to root or default group
        print("Adding file to root group")
        target_group = None
    
    # Validate target names if specified
    validated_target_names = None
    if target_names:
        validated_target_names = []
        for target_name in target_names:
            target = get_target_by_name(project, target_name)
            if target:
                validated_target_names.append(target_name)  # Store the NAME, not the object
                print(f"Will add to target: {target_name}")
            else:
                print(f"Warning: Target '{target_name}' not found")
        
        if not validated_target_names:
            print("Warning: No valid targets found, file will be added to all default targets")
            validated_target_names = None
    
    # Add file with or without target specification
    # Note: target_name parameter expects target names as strings, not target objects
    if target_group:
        project.add_file(str(relative_file_path), parent=target_group, target_name=validated_target_names, force=False)
    else:
        project.add_file(str(relative_file_path), target_name=validated_target_names, force=False)

def remove_file_from_groups(project, project_root, file_path):
    """
    Remove a file from the project, handling both aliases and regular file references.
    
    Args:
        project: The XcodeProject instance
        project_root: The root directory of the project
        file_path: The absolute path to the file
    """
    absolute_file_path = Path(file_path).resolve()
    relative_file_path = absolute_file_path.relative_to(project_root)
    
    print(f"Removing file: {relative_file_path}")
    
    # Try the standard removal first (works for aliases)
    try:
        project.remove_files_by_path(str(relative_file_path))
        print("File removed successfully (standard method)")
        return
    except:
        print("Standard removal failed, trying alternative methods...")
    
    # Alternative method: Find and remove file references manually
    file_removed = False
    relative_path_str = str(relative_file_path)
    filename = Path(file_path).name
    
    # Find all file references that match
    file_refs_to_remove = []
    for obj_id in project.objects:
        obj = project.objects[obj_id]
        
        # Check if it's a PBXFileReference
        if hasattr(obj, 'isa') and obj.isa == 'PBXFileReference':
            # Match by path or name
            matches = False
            if hasattr(obj, 'path') and obj.path:
                if obj.path == relative_path_str or obj.path.endswith(filename):
                    matches = True
            if hasattr(obj, 'name') and obj.name == filename:
                matches = True
            
            if matches:
                file_refs_to_remove.append((obj_id, obj))
                print(f"Found file reference: {obj_id} - path: {getattr(obj, 'path', 'N/A')}, name: {getattr(obj, 'name', 'N/A')}")
    
    # Remove from build phases first
    for file_ref_id, file_ref in file_refs_to_remove:
        # Find all build files that reference this file
        for phase_type in ['PBXSourcesBuildPhase', 'PBXResourcesBuildPhase', 'PBXFrameworksBuildPhase', 'PBXHeadersBuildPhase']:
            for phase in project.objects.get_objects_in_section(phase_type):
                if hasattr(phase, 'files') and phase.files:
                    files_to_remove = []
                    for build_file_id in list(phase.files):  # Make a copy to avoid modification during iteration
                        if build_file_id in project.objects:
                            build_file = project.objects[build_file_id]
                            if hasattr(build_file, 'fileRef') and build_file.fileRef == file_ref_id:
                                files_to_remove.append(build_file_id)
                                print(f"Removing from {phase_type}: {build_file_id}")
                    
                    # Remove the build files
                    for build_file_id in files_to_remove:
                        if build_file_id in phase.files:
                            phase.files.remove(build_file_id)
                        # Also remove the build file object
                        if build_file_id in project.objects:
                            del project.objects[build_file_id]
                        file_removed = True
    
    # Remove from groups
    for file_ref_id, file_ref in file_refs_to_remove:
        # Find parent groups
        for group in project.objects.get_objects_in_section('PBXGroup'):
            if hasattr(group, 'children') and group.children:
                if file_ref_id in group.children:
                    group.children.remove(file_ref_id)
                    print(f"Removed from group: {getattr(group, 'name', 'unnamed')}")
                    file_removed = True
    
    # Remove the file reference objects themselves
    for file_ref_id, file_ref in file_refs_to_remove:
        if file_ref_id in project.objects:
            del project.objects[file_ref_id]
            print(f"Removed file reference object: {file_ref_id}")
            file_removed = True
    
    if file_removed:
        print("File removed successfully (manual method)")
    else:
        print("Warning: File not found in project")

def find_xcodeproj(start_path):
    """
    Find .xcodeproj file starting from a given path.
    Searches current directory and parent directories.
    
    Args:
        start_path: Path to start searching from
    
    Returns:
        Path to .xcodeproj directory or None if not found
    """
    current = Path(start_path).resolve()
    
    # If start_path is already an xcodeproj, use it
    if current.suffix == '.xcodeproj' and current.exists():
        return current
    
    # Search current directory and parents
    while current != current.parent:
        # Look for .xcodeproj in current directory
        for item in current.iterdir():
            if item.suffix == '.xcodeproj' and item.is_dir():
                return item
        current = current.parent
    
    return None

def main():
    parser = ArgumentParser(
        description="Universal Xcode project file manager with automatic group management and target specification."
    )
    parser.add_argument(
        'action',
        choices=['add', 'remove'],
        help="The action to perform: 'add' to add a file (creating groups as needed), 'remove' to remove a file."
    )
    parser.add_argument(
        'file_path',
        help='The full or relative path to the file to add or remove.'
    )
    parser.add_argument(
        '--project',
        help='Path to .xcodeproj file or directory containing it. If not specified, searches from current directory upwards.'
    )
    parser.add_argument(
        '--no-groups',
        action='store_true',
        help='When adding, do not create groups based on folder structure (add to root instead).'
    )
    parser.add_argument(
        '--targets',
        nargs='+',
        help='Specific target(s) to add the file to. If not specified, file is added to all default targets. Examples: --targets MyApp MyFramework'
    )
    
    args = parser.parse_args()

    try:
        # Find the Xcode project
        if args.project:
            xcodeproj_path = Path(args.project).resolve()
            if xcodeproj_path.suffix != '.xcodeproj':
                # Assume it's a directory, look inside it
                found = find_xcodeproj(xcodeproj_path)
                if found:
                    xcodeproj_path = found
                else:
                    print(f"Error: No .xcodeproj found in '{args.project}'", file=sys.stderr)
                    sys.exit(1)
        else:
            # Search from current directory
            xcodeproj_path = find_xcodeproj(Path.cwd())
            if not xcodeproj_path:
                print("Error: No .xcodeproj found in current directory or parent directories.", file=sys.stderr)
                print("Please specify --project path/to/Project.xcodeproj", file=sys.stderr)
                sys.exit(1)
        
        if not xcodeproj_path.exists():
            print(f"Error: Project not found at '{xcodeproj_path}'", file=sys.stderr)
            sys.exit(1)
        
        pbxproj_path = xcodeproj_path / "project.pbxproj"
        if not pbxproj_path.exists():
            print(f"Error: project.pbxproj not found in '{xcodeproj_path}'", file=sys.stderr)
            sys.exit(1)
        
        # Project root is the parent of .xcodeproj
        project_root = xcodeproj_path.parent
        
        print(f"Using Xcode project: {xcodeproj_path.name}")
        print(f"Project root: {project_root}")
        
        # Get the absolute path of the file
        file_path_input = Path(args.file_path)
        if file_path_input.is_absolute():
            absolute_file_path = file_path_input.resolve()
        else:
            # Relative to current directory
            absolute_file_path = (Path.cwd() / file_path_input).resolve()
        
        # Verify the file is within the project directory (for add) or just resolve path (for remove)
        try:
            relative_file_path = absolute_file_path.relative_to(project_root)
        except ValueError:
            if args.action == 'add':
                print(
                    f"Error: The file '{absolute_file_path}' is not inside the project root '{project_root}'.",
                    file=sys.stderr
                )
                sys.exit(1)
            # For remove, we can try with the path as-is
            relative_file_path = Path(args.file_path)
        
        print(f"File path: {absolute_file_path}")
        print(f"Relative path: {relative_file_path}")
        
        # Load the project
        print(f"\nLoading project: {pbxproj_path}")
        project = XcodeProject.load(str(pbxproj_path))
        
        # Show available targets if requested
        if args.targets:
            print(f"\nAvailable targets in project:")
            for target in project.objects.get_targets():
                print(f"  - {target.name}")
            print()
        
        # Perform the requested action
        if args.action == 'add':
            if args.no_groups:
                print("\nAdding file without group management...")
                validated_target_names = None
                if args.targets:
                    validated_target_names = []
                    for target_name in args.targets:
                        target = get_target_by_name(project, target_name)
                        if target:
                            validated_target_names.append(target_name)  # Store the NAME, not the object
                            print(f"Will add to target: {target_name}")
                        else:
                            print(f"Warning: Target '{target_name}' not found")
                    if not validated_target_names:
                        validated_target_names = None
                
                project.add_file(str(relative_file_path), target_name=validated_target_names, force=False)
            else:
                print("\nAdding file with automatic group management...")
                add_file_with_groups(project, project_root, absolute_file_path, args.targets)
            
            print(f"\nFile '{relative_file_path}' successfully added.")
            
        elif args.action == 'remove':
            print("\nRemoving file from project...")
            remove_file_from_groups(project, project_root, absolute_file_path)
            print(f"\nFile '{relative_file_path}' successfully removed.")
        
        # Save the project
        project.save()
        print("Project saved successfully.")
        
    except FileNotFoundError as e:
        print(f"Error: File not found - {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
