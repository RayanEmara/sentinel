import AppKit
import SwiftMath

let latex = """
\\begin{aligned}  \\left\\lvert B(u,u)   \\right\\rvert &= 0 \\\\
&\\not \\geq \\beta \\left\\| u \\right\\|_{V}^2 = \\beta \\int_{\\Omega}^{}\\left( \\left\\lvert \\overset{=0}{\\nabla u} \\right\\rvert^2 \\right) + \\left\\lvert 5 \\right\\rvert^2 = \\beta \\cdot 25
\\end{aligned}
"""

let label = MTMathUILabel()
label.latex = latex

print("--- Testing Equation 1 ---")
print("Error: \(String(describing: label.error))")

let latex2 = "\\langle u,u\\rangle_V = 0 \\quad \\centernot\\iff \\quad u = 0."
label.latex = latex2
print("--- Testing Equation 2 ---")
print("Error: \(String(describing: label.error))")
