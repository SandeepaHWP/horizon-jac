"""What the api answers the gate with where the answer is more than a value: the status the
original sends and its JSON body."""
obj Reply {
    has status: int,
        body: str;
}
