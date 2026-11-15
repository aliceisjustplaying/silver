@ gray_bgra(const uint32_t *src, uint32_t *dst, int npix, const uint32_t *lut)
@ BGRA (little-endian 0xAARRGGBB) -> luma Y = (29*B + 150*G + 77*R) >> 8,
@ then dst = lut[Y]. npix must be a multiple of 4. ARMv6 media instructions.
	.text
	.align 2
	.globl _gray_bgra
_gray_bgra:
	stmfd	sp!, {r4-r11, lr}
	mov	r4, #0x1d		@ lane0 = B*29
	orr	r4, r4, #0x4d0000	@ lane1 = R*77
	mov	r5, #150		@ lane0 = G*150, lane1 = A*0
Lgray_loop:
	ldmia	r0!, {r6-r9}
	uxtb16	r10, r6			@ B0, R0
	uxtb16	r11, r6, ror #8		@ G0, A0
	uxtb16	r12, r7			@ B1, R1
	uxtb16	lr, r7, ror #8		@ G1, A1
	smuad	r10, r10, r4
	smuad	r12, r12, r4
	smlad	r10, r11, r5, r10
	smlad	r12, lr, r5, r12
	uxtb	r10, r10, ror #8
	uxtb	r12, r12, ror #8
	uxtb16	r11, r8
	uxtb16	lr, r8, ror #8
	ldr	r6, [r3, r10, lsl #2]
	ldr	r7, [r3, r12, lsl #2]
	smuad	r11, r11, r4
	uxtb16	r10, r9
	uxtb16	r12, r9, ror #8
	smlad	r11, lr, r5, r11
	smuad	r10, r10, r4
	uxtb	r11, r11, ror #8
	smlad	r10, r12, r5, r10
	ldr	r8, [r3, r11, lsl #2]
	uxtb	r10, r10, ror #8
	subs	r2, r2, #4
	ldr	r9, [r3, r10, lsl #2]
	stmia	r1!, {r6-r9}
	bgt	Lgray_loop
	ldmfd	sp!, {r4-r11, pc}
