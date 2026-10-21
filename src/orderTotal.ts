export type OrderLine = { unitPriceCents: number; quantity: number }

export function orderTotalCents(lines: OrderLine[]): number {
  return lines.reduce(
    (sum, line) => sum + line.unitPriceCents * line.quantity,
    0,
  )
}
