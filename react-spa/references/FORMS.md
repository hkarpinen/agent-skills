# Zod Schemas

Schemas are the single source of truth for both form validation and API response
parsing.

```ts
// src/schemas/order.ts
import { z } from "zod";

export const orderLineSchema = z.object({
  productId: z.string().uuid(),
  quantity: z.number().int().positive(),
});

export const placeOrderSchema = z.object({
  customerId: z.string().uuid(),
  lines: z.array(orderLineSchema).min(1, "At least one line required"),
});

export const orderSchema = z.object({
  id: z.string().uuid(),
  customerId: z.string().uuid(),
  status: z.enum(["draft", "pending", "confirmed", "cancelled"]),
  lines: z.array(orderLineSchema),
  createdAt: z.string().datetime(),
});

export type Order = z.infer<typeof orderSchema>;
export type PlaceOrderPayload = z.infer<typeof placeOrderSchema>;
```

Rules:
- Derive TypeScript types from schemas with `z.infer<>` — never define the
  type separately.
- Use the *same* schema object for `react-hook-form` validation and for
  `queryFn` response parsing.
- Place schemas in `src/schemas/` when shared across API hooks and forms.

---

# React Hook Form + Zod

```tsx
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { placeOrderSchema, type PlaceOrderPayload } from "@/schemas/order";
import { usePlaceOrder } from "@/api/orders";

export function PlaceOrderForm() {
  const { mutate, isPending } = usePlaceOrder();

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<PlaceOrderPayload>({
    resolver: zodResolver(placeOrderSchema),
  });

  const onSubmit = (data: PlaceOrderPayload) => mutate(data);

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <input {...register("customerId")} placeholder="Customer ID" />
      {errors.customerId && <p>{errors.customerId.message}</p>}

      <button type="submit" disabled={isPending}>
        {isPending ? "Placing…" : "Place Order"}
      </button>
    </form>
  );
}
```

Rules:
- Always use `zodResolver` — never write manual validation in `react-hook-form`.
- Disable the submit button while `isPending` to prevent double-submission.
- Show field-level errors inline, not as a toast or alert.
- For complex forms with dynamic arrays, use `useFieldArray` from
  `react-hook-form`.
