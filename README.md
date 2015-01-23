# SOA
Automatically re-implement arrays of structures as structures of arrays.

```d
struct Vector3 { float x = 1.0, y = 2.0, z = 3.0; }
Vector3[100] vectors1;
SOA!(Vector3[100]) vectors2;

// vectors1 is laid out in memory as an array of structs:
// [ 1, 2, 3, 1, 2, 3, 1, 2, 3, ...]

// vectors2 is laid out in memory as a struct of arrays:
// [ 1, 1, 1, ..., 2, 2, 2, ..., 3, 3, 3, ...]
```

See the module documentation for more information and features.
