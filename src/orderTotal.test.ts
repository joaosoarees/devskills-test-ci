import { describe, expect, it } from 'vitest'
import { orderTotalCents } from './orderTotal'

describe('orderTotalCents', () => {
  it('adds price times quantity of every line', () => {
    expect(
      orderTotalCents([
        { unitPriceCents: 1250, quantity: 2 },
        { unitPriceCents: 300, quantity: 1 },
      ]),
    ).toBe(2800)
  })
})
