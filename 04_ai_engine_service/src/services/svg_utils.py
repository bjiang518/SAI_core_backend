"""
SVG utility functions for diagram processing
"""

import re
from typing import Optional


def add_svg_padding(svg_code: str, padding: int = 20) -> str:
    """
    Add padding to SVG by expanding the viewBox

    This prevents content from being cropped at edges, especially
    at bottom and left edges where clipping commonly occurs.

    Args:
        svg_code: Original SVG code
        padding: Padding to add in all directions (default: 20)

    Returns:
        Modified SVG code with expanded viewBox
    """
    try:
        # Find viewBox attribute
        viewbox_pattern = r'viewBox=["\']([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)["\']'
        viewbox_match = re.search(viewbox_pattern, svg_code)

        if viewbox_match:
            # Extract current viewBox values
            min_x = float(viewbox_match.group(1))
            min_y = float(viewbox_match.group(2))
            width = float(viewbox_match.group(3))
            height = float(viewbox_match.group(4))

            # Add padding by:
            # 1. Moving min_x and min_y negative (expand left/top)
            # 2. Increasing width and height (expand right/bottom)
            new_min_x = min_x - padding
            new_min_y = min_y - padding
            new_width = width + (2 * padding)
            new_height = height + (2 * padding)

            # Create new viewBox string
            new_viewbox = f'viewBox="{new_min_x} {new_min_y} {new_width} {new_height}"'

            # Replace old viewBox with new one
            modified_svg = re.sub(viewbox_pattern, new_viewbox, svg_code)

            print(f"✅ [SVG Padding] Original viewBox: {min_x} {min_y} {width} {height}")
            print(f"✅ [SVG Padding] New viewBox: {new_min_x} {new_min_y} {new_width} {new_height}")

            return modified_svg
        else:
            # No viewBox found - try to extract width/height and create viewBox
            print(f"⚠️ [SVG Padding] No viewBox found, attempting to extract width/height")

            width_match = re.search(r'width=["\']([\d.]+)(?:px)?["\']', svg_code)
            height_match = re.search(r'height=["\']([\d.]+)(?:px)?["\']', svg_code)

            if width_match and height_match:
                width = float(width_match.group(1))
                height = float(height_match.group(1))

                # Create viewBox with padding
                new_viewbox = f'viewBox="{-padding} {-padding} {width + 2*padding} {height + 2*padding}"'

                # Insert viewBox after opening <svg tag
                svg_with_viewbox = re.sub(
                    r'(<svg[^>]*)',
                    f'\\1 {new_viewbox}',
                    svg_code,
                    count=1
                )

                print(f"✅ [SVG Padding] Created viewBox from dimensions: {width}x{height}")
                return svg_with_viewbox
            else:
                # Can't determine dimensions - return original
                print(f"⚠️ [SVG Padding] Cannot determine SVG dimensions, returning original")
                return svg_code

    except Exception as e:
        print(f"❌ [SVG Padding] Error adding padding: {e}")
        return svg_code


def ensure_svg_has_dimensions(svg_code: str, default_width: int = 400, default_height: int = 300) -> str:
    """
    Ensure SVG has width and height attributes

    Some SVG generators omit these, which can cause rendering issues

    Args:
        svg_code: Original SVG code
        default_width: Default width if none specified
        default_height: Default height if none specified

    Returns:
        SVG code with width/height attributes
    """
    try:
        # Check if width/height already exist
        has_width = re.search(r'width=', svg_code)
        has_height = re.search(r'height=', svg_code)

        if has_width and has_height:
            return svg_code

        # Extract from viewBox if available
        viewbox_match = re.search(r'viewBox=["\']([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)["\']', svg_code)

        if viewbox_match:
            width = float(viewbox_match.group(3))
            height = float(viewbox_match.group(4))
        else:
            width = default_width
            height = default_height

        # Add width/height after <svg tag
        modified_svg = re.sub(
            r'(<svg[^>]*)',
            f'\\1 width="{int(width)}" height="{int(height)}"',
            svg_code,
            count=1
        )

        print(f"✅ [SVG Dimensions] Added dimensions: {int(width)}x{int(height)}")
        return modified_svg

    except Exception as e:
        print(f"❌ [SVG Dimensions] Error adding dimensions: {e}")
        return svg_code


def optimize_svg_for_display(svg_code: str, padding: int = 20) -> str:
    """
    Apply all SVG optimizations for display

    - Add padding to prevent cropping
    - Ensure dimensions are present

    Args:
        svg_code: Original SVG code
        padding: Padding to add (default: 20)

    Returns:
        Optimized SVG code
    """
    # Step 1: Add padding to viewBox
    svg_with_padding = add_svg_padding(svg_code, padding)

    # Step 2: Ensure dimensions
    optimized_svg = ensure_svg_has_dimensions(svg_with_padding)

    return optimized_svg
