"""
External LaTeX Rendering Service
Uses QuickLaTeX API or similar service for LaTeX to image conversion
"""

import aiohttp
import base64
from typing import Dict
from .svg_utils import optimize_svg_for_display


class ExternalLaTeXRenderer:
    """Render LaTeX using external API service"""

    QUICKLATEX_API = "https://quicklatex.com/latex3.f"

    async def render_latex_to_svg(self, latex_code: str,
                                   width: int = 400,
                                   height: int = 300) -> Dict:
        """
        Render LaTeX using QuickLaTeX API.

        QuickLaTeX is a free service for LaTeX rendering.
        Alternatives: latex.codecogs.com, mathpix.com

        Returns SVG code ready for iOS rendering.
        """
        print(f"🎨 [ExternalLaTeX] Rendering via QuickLaTeX API...")

        try:
            # Prepare LaTeX document
            latex_document = f"""
\\documentclass[border=2pt]{{standalone}}
\\usepackage{{tikz}}
\\usetikzlibrary{{arrows,shapes,positioning}}
\\begin{{document}}
{latex_code}
\\end{{document}}
"""

            # QuickLaTeX API parameters
            payload = {
                'formula': latex_document,
                'fsize': '18px',  # Font size
                'fcolor': '000000',  # Black
                'mode': '0',  # Inline mode
                'out': '1',  # SVG output (if supported)
                'errors': '1',  # Return errors
                'preamble': '\\usepackage{tikz}\\usetikzlibrary{arrows,shapes}'
            }

            async with aiohttp.ClientSession() as session:
                async with session.post(
                    self.QUICKLATEX_API,
                    data=payload,
                    timeout=aiohttp.ClientTimeout(total=10)
                ) as response:
                    result_text = await response.text()

                    # Parse QuickLaTeX response
                    # Format: "0\nurl_to_image\nwidth height"
                    lines = result_text.strip().split('\n')

                    if lines[0] != '0':
                        # Error occurred
                        error_msg = lines[1] if len(lines) > 1 else "Unknown error"
                        print(f"❌ [ExternalLaTeX] Rendering failed: {error_msg}")
                        return {
                            'success': False,
                            'svg_code': None,
                            'error': f"LaTeX rendering error: {error_msg}"
                        }

                    # Success - get image URL
                    image_url = lines[1]
                    print(f"✅ [ExternalLaTeX] Rendered successfully: {image_url}")

                    # Download the rendered image
                    async with session.get(image_url) as img_response:
                        image_data = await img_response.read()

                        # Convert to base64 data URI for embedding
                        # (Or convert PNG to SVG using additional service)
                        image_b64 = base64.b64encode(image_data).decode()

                        # Wrap in SVG with embedded image
                        svg_code = f'''<svg xmlns="http://www.w3.org/2000/svg"
                                          width="{width}" height="{height}"
                                          viewBox="0 0 {width} {height}">
                            <image href="data:image/png;base64,{image_b64}"
                                   x="0" y="0" width="{width}" height="{height}"/>
                        </svg>'''

                        # ✅ FIX: Add padding to prevent cropping at edges
                        svg_optimized = optimize_svg_for_display(svg_code, padding=20)

                        return {
                            'success': True,
                            'svg_code': svg_optimized,
                            'error': None
                        }

        except aiohttp.ClientTimeout:
            return {
                'success': False,
                'svg_code': None,
                'error': "External LaTeX API timeout (>10s)"
            }
        except Exception as e:
            print(f"❌ [ExternalLaTeX] Error: {str(e)}")
            return {
                'success': False,
                'svg_code': None,
                'error': str(e)
            }


# Alternative: LaTeX.codecogs.com (even simpler)
class CodecogsLaTeXRenderer:
    """Use LaTeX.codecogs.com for quick rendering"""

    BASE_URL = "https://latex.codecogs.com/svg.latex"

    async def render_latex_simple(self, latex_code: str) -> str:
        """
        Simple LaTeX rendering using Codecogs.

        Just returns URL to SVG, let iOS fetch it:
        https://latex.codecogs.com/svg.latex?y=x^2+5x+6
        """
        import urllib.parse

        encoded = urllib.parse.quote(latex_code)
        svg_url = f"{self.BASE_URL}?{encoded}"

        print(f"🎨 [Codecogs] Generated URL: {svg_url}")

        # Return SVG with external image reference
        svg_code = f'''<svg xmlns="http://www.w3.org/2000/svg"
                          width="400" height="300" viewBox="0 0 400 300">
            <image href="{svg_url}" x="0" y="0" width="400" height="300"/>
        </svg>'''

        return svg_code


# Usage in generate_latex_diagram:
"""
async def generate_latex_diagram(...):
    # ... existing code generates LaTeX ...

    # Use external rendering
    renderer = ExternalLaTeXRenderer()
    conversion_result = await renderer.render_latex_to_svg(latex_code, width, height)

    if conversion_result['success']:
        result['diagram_type'] = 'svg'
        result['diagram_code'] = conversion_result['svg_code']
        return result
"""
