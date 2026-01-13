"""
LaTeX to SVG Conversion Service
Converts TikZ/LaTeX diagrams to SVG for client-side rendering
"""

import subprocess
import tempfile
import os
from typing import Dict, Optional


class LaTeXConverter:
    """Convert LaTeX/TikZ code to SVG format"""

    def __init__(self):
        self.temp_dir = tempfile.gettempdir()

    async def convert_tikz_to_svg(self, tikz_code: str,
                                  title: str = "Diagram",
                                  width: int = 400,
                                  height: int = 300) -> Dict:
        """
        Convert TikZ code to SVG using pdflatex + pdf2svg (system commands).

        Args:
            tikz_code: TikZ code (e.g., \\begin{tikzpicture}...\\end{tikzpicture})
            title: Diagram title for accessibility
            width: Target width in pixels
            height: Target height in pixels

        Returns:
            Dict with 'success', 'svg_code', 'error' keys
        """
        import time
        start_time = time.time()

        try:
            # Use pdflatex + pdf2svg (system commands installed in Dockerfile)
            result = await self._convert_with_pdflatex(tikz_code, width, height)

            elapsed_ms = int((time.time() - start_time) * 1000)

            if result['success']:
                print(f"✅ LaTeX: Converted to SVG in {elapsed_ms}ms")
                return result
            else:
                print(f"❌ LaTeX: Failed in {elapsed_ms}ms - {result.get('error', 'Unknown')}")
                return result

        except Exception as e:
            elapsed_ms = int((time.time() - start_time) * 1000)
            print(f"❌ LaTeX: Exception in {elapsed_ms}ms - {str(e)}")
            return {
                'success': False,
                'svg_code': None,
                'error': f"LaTeX conversion error: {str(e)}"
            }

    async def _convert_with_pdflatex(self, tikz_code: str,
                                     width: int, height: int) -> Dict:
        """Convert using pdflatex + pdf2svg (fallback method)"""
        import uuid

        # Generate unique filenames
        file_id = str(uuid.uuid4())[:8]
        tex_file = os.path.join(self.temp_dir, f"diagram_{file_id}.tex")
        pdf_file = os.path.join(self.temp_dir, f"diagram_{file_id}.pdf")
        svg_file = os.path.join(self.temp_dir, f"diagram_{file_id}.svg")

        try:
            # Create LaTeX document
            latex_document = f"""
\\documentclass[tikz,border=2pt]{{standalone}}
\\usepackage{{tikz}}
\\usetikzlibrary{{arrows,shapes,positioning,calc,patterns}}
\\begin{{document}}
{tikz_code}
\\end{{document}}
"""

                        # Write to file
            with open(tex_file, 'w', encoding='utf-8') as f:
                f.write(latex_document)

            # Compile LaTeX to PDF
            compile_result = subprocess.run(
                ['pdflatex',
                 '-interaction=nonstopmode',
                 '-halt-on-error',
                 '-file-line-error',
                 '-output-directory', self.temp_dir,
                 tex_file],
                capture_output=True,
                text=True,
                timeout=45
            )

            # Check if PDF was created
            if not os.path.exists(pdf_file):
                return {
                    'success': False,
                    'svg_code': None,
                    'error': f"LaTeX compilation failed - no PDF output"
                }

            # Convert PDF to SVG using pdf2svg or dvisvgm
            try:
                subprocess.run(
                    ['pdf2svg', pdf_file, svg_file],
                    check=True,
                    timeout=15
                )
            except (subprocess.CalledProcessError, FileNotFoundError):
                subprocess.run(
                    ['dvisvgm', '--pdf', '--optimize', '--output=' + svg_file, pdf_file],
                    check=True,
                    timeout=15
                )

            # Read SVG content
            with open(svg_file, 'r', encoding='utf-8') as f:
                svg_code = f.read()

            # Add metadata
            svg_code = self._add_svg_metadata(svg_code, width, height)

            return {
                'success': True,
                'svg_code': svg_code,
                'error': None
            }

        except subprocess.TimeoutExpired:
            return {
                'success': False,
                'svg_code': None,
                'error': "LaTeX compilation timeout (>45s)"
            }
        except Exception as e:
            return {
                'success': False,
                'svg_code': None,
                'error': str(e)
            }
        finally:
            # Cleanup temp files
            for file in [tex_file, pdf_file, svg_file]:
                try:
                    if os.path.exists(file):
                        os.remove(file)
                except:
                    pass

    def _add_svg_metadata(self, svg_code: str, width: int, height: int) -> str:
        """Add proper viewBox and dimensions to SVG"""
        import re

        # If SVG already has width/height, extract viewBox
        if 'viewBox' not in svg_code:
            # Add viewBox based on dimensions
            svg_code = svg_code.replace(
                '<svg',
                f'<svg viewBox="0 0 {width} {height}"',
                1
            )

        # Ensure SVG has proper namespace
        if 'xmlns' not in svg_code:
            svg_code = svg_code.replace(
                '<svg',
                '<svg xmlns="http://www.w3.org/2000/svg"',
                1
            )

        # Add accessibility attributes
        svg_code = svg_code.replace(
            '<svg',
            '<svg role="img" aria-label="Educational diagram"',
            1
        )

        return svg_code


# Singleton instance
latex_converter = LaTeXConverter()
