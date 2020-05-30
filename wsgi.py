def application(environ=None, start_response=None):
    print("HANDLING REQUEST", environ)
    global num
    num += 1
    start_response("200 OK", [])
    return [str(num).encode()] if num % 2 == 1 else [str(num)]
